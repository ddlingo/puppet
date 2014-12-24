#!/usr/bin/env ruby

require 'spec_helper'

require 'puppet/util/windows'

describe Puppet::Util::Windows::ADSI, :if => Puppet.features.microsoft_windows? do
  let(:connection) { double 'connection' }

  before(:each) do
    Puppet::Util::Windows::ADSI.instance_variable_set(:@computer_name, 'testcomputername')
    Puppet::Util::Windows::ADSI.stubs(:connect).returns connection
  end

  after(:each) do
    Puppet::Util::Windows::ADSI.instance_variable_set(:@computer_name, nil)
  end

  it "should generate the correct URI for a resource" do
    expect(Puppet::Util::Windows::ADSI.uri('test', 'user')).to eq("WinNT://./test,user")
  end

  it "should be able to get the name of the computer" do
    expect(Puppet::Util::Windows::ADSI.computer_name).to eq('testcomputername')
  end

  it "should be able to provide the correct WinNT base URI for the computer" do
    expect(Puppet::Util::Windows::ADSI.computer_uri).to eq("WinNT://.")
  end

  it "should generate a fully qualified WinNT URI" do
    expect(Puppet::Util::Windows::ADSI.computer_uri('testcomputername')).to eq("WinNT://testcomputername")
  end

  describe ".computer_name" do
    it "should return a non-empty ComputerName string" do
      Puppet::Util::Windows::ADSI.instance_variable_set(:@computer_name, nil)
      expect(Puppet::Util::Windows::ADSI.computer_name).not_to be_empty
    end
  end

  describe ".sid_uri" do
    it "should raise an error when the input is not a SID object" do
      [Object.new, {}, 1, :symbol, '', nil].each do |input|
        expect {
          Puppet::Util::Windows::ADSI.sid_uri(input)
        }.to raise_error(Puppet::Error, /Must use a valid SID object/)
      end
    end

    it "should return a SID uri for a well-known SID (SYSTEM)" do
      sid = Win32::Security::SID.new('SYSTEM')
      expect(Puppet::Util::Windows::ADSI.sid_uri(sid)).to eq('WinNT://S-1-5-18')
    end
  end

  describe Puppet::Util::Windows::ADSI::User do
    let(:username)  { 'testuser' }
    let(:domain)    { 'DOMAIN' }
    let(:domain_username) { "#{domain}\\#{username}"}

    it "should generate the correct URI" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      expect(Puppet::Util::Windows::ADSI::User.uri(username)).to eq("WinNT://./#{username},user")
    end

    it "should generate the correct URI for a user with a domain" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      expect(Puppet::Util::Windows::ADSI::User.uri(username, domain)).to eq("WinNT://#{domain}/#{username},user")
    end

    it "should be able to parse a username without a domain" do
      expect(Puppet::Util::Windows::ADSI::User.parse_name(username)).to eq([username, '.'])
    end

    it "should be able to parse a username with a domain" do
      expect(Puppet::Util::Windows::ADSI::User.parse_name(domain_username)).to eq([username, domain])
    end

    it "should raise an error with a username that contains a /" do
      expect {
        Puppet::Util::Windows::ADSI::User.parse_name("#{domain}/#{username}")
      }.to raise_error(Puppet::Error, /Value must be in DOMAIN\\user style syntax/)
    end

    it "should be able to create a user" do
      adsi_user = double('adsi')

      connection.expects(:Create).with('user', username).returns(adsi_user)
      Puppet::Util::Windows::ADSI::Group.expects(:exists?).with(username).returns(false)

      user = Puppet::Util::Windows::ADSI::User.create(username)

      expect(user).to be_a(Puppet::Util::Windows::ADSI::User)
      expect(user.native_user).to eq(adsi_user)
    end

    it "should be able to check the existence of a user" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      Puppet::Util::Windows::ADSI.expects(:connect).with("WinNT://./#{username},user").returns connection
      expect(Puppet::Util::Windows::ADSI::User.exists?(username)).to be_truthy
    end

    it "should be able to check the existence of a domain user" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      Puppet::Util::Windows::ADSI.expects(:connect).with("WinNT://#{domain}/#{username},user").returns connection
      expect(Puppet::Util::Windows::ADSI::User.exists?(domain_username)).to be_truthy
    end

    it "should be able to confirm the existence of a user with a well-known SID" do

      system_user = Win32::Security::SID::LocalSystem
      # ensure that the underlying OS is queried here
      allow(Puppet::Util::Windows::ADSI).to receive(:connect).and_call_original
      expect(Puppet::Util::Windows::ADSI::User.exists?(system_user)).to be_truthy
    end

    it "should return nil with an unknown SID" do

      bogus_sid = 'S-1-2-3-4'
      # ensure that the underlying OS is queried here
      allow(Puppet::Util::Windows::ADSI).to receive(:connect).and_call_original
      expect(Puppet::Util::Windows::ADSI::User.exists?(bogus_sid)).to be_falsey
    end

    it "should be able to delete a user" do
      connection.expects(:Delete).with('user', username)

      Puppet::Util::Windows::ADSI::User.delete(username)
    end

    it "should return an enumeration of IADsUser wrapped objects" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)

      name = 'Administrator'
      wmi_users = [double('WMI', :name => name)]
      Puppet::Util::Windows::ADSI.expects(:execquery).with('select name from win32_useraccount where localaccount = "TRUE"').returns(wmi_users)

      native_user = double('IADsUser')
      homedir = "C:\\Users\\#{name}"
      native_user.expects(:Get).with('HomeDirectory').returns(homedir)
      Puppet::Util::Windows::ADSI.expects(:connect).with("WinNT://./#{name},user").returns(native_user)

      users = Puppet::Util::Windows::ADSI::User.to_a
      expect(users.length).to eq(1)
      expect(users[0].name).to eq(name)
      expect(users[0]['HomeDirectory']).to eq(homedir)
    end

    describe "an instance" do
      let(:adsi_user) { double('user', :objectSID => []) }
      let(:sid)       { double(:account => username, :domain => 'testcomputername') }
      let(:user)      { Puppet::Util::Windows::ADSI::User.new(username, adsi_user) }

      it "should provide its groups as a list of names" do
        names = ["group1", "group2"]

        groups = names.map { |name| double('group', :Name => name) }

        adsi_user.expects(:Groups).returns(groups)

        expect(user.groups).to match(names)
      end

      it "should be able to test whether a given password is correct" do
        Puppet::Util::Windows::ADSI::User.expects(:logon).with(username, 'pwdwrong').returns(false)
        Puppet::Util::Windows::ADSI::User.expects(:logon).with(username, 'pwdright').returns(true)

        expect(user.password_is?('pwdwrong')).to be_falsey
        expect(user.password_is?('pwdright')).to be_truthy
      end

      it "should be able to set a password" do
        adsi_user.expects(:SetPassword).with('pwd')
        adsi_user.expects(:SetInfo).at_least_once

        flagname = "UserFlags"
        fADS_UF_DONT_EXPIRE_PASSWD = 0x10000

        adsi_user.expects(:Get).with(flagname).returns(0)
        adsi_user.expects(:Put).with(flagname, fADS_UF_DONT_EXPIRE_PASSWD)

        user.password = 'pwd'
      end

      it "should generate the correct URI" do
        Puppet::Util::Windows::SID.stubs(:octet_string_to_sid_object).returns(sid)
        expect(user.uri).to eq("WinNT://testcomputername/#{username},user")
      end

      describe "when given a set of groups to which to add the user" do
        let(:groups_to_set) { 'group1,group2' }

        before(:each) do
          Puppet::Util::Windows::SID.stubs(:octet_string_to_sid_object).returns(sid)
          user.expects(:groups).returns ['group2', 'group3']
        end

        describe "if membership is specified as inclusive" do
          it "should add the user to those groups, and remove it from groups not in the list" do
            group1 = double 'group1'
            group1.expects(:Add).with("WinNT://testcomputername/#{username},user")

            group3 = double 'group1'
            group3.expects(:Remove).with("WinNT://testcomputername/#{username},user")

            Puppet::Util::Windows::ADSI.expects(:sid_uri).with(sid).returns("WinNT://testcomputername/#{username},user").twice
            Puppet::Util::Windows::ADSI.expects(:connect).with('WinNT://./group1,group').returns group1
            Puppet::Util::Windows::ADSI.expects(:connect).with('WinNT://./group3,group').returns group3

            user.set_groups(groups_to_set, false)
          end
        end

        describe "if membership is specified as minimum" do
          it "should add the user to the specified groups without affecting its other memberships" do
            group1 = double 'group1'
            group1.expects(:Add).with("WinNT://testcomputername/#{username},user")

            Puppet::Util::Windows::ADSI.expects(:sid_uri).with(sid).returns("WinNT://testcomputername/#{username},user")
            Puppet::Util::Windows::ADSI.expects(:connect).with('WinNT://./group1,group').returns group1

            user.set_groups(groups_to_set, true)
          end
        end
      end
    end
  end

  describe Puppet::Util::Windows::ADSI::Group do
    let(:groupname)  { 'testgroup' }

    describe "an instance" do
      let(:adsi_group) { double 'group' }
      let(:group)      { Puppet::Util::Windows::ADSI::Group.new(groupname, adsi_group) }
      let(:someone_sid){ double(:account => 'someone', :domain => 'testcomputername')}

      describe "should be able to use SID objects" do
        let(:system)     { Puppet::Util::Windows::SID.name_to_sid_object('SYSTEM') }
        let(:invalid)    { Puppet::Util::Windows::SID.name_to_sid_object('foobar') }

        it "to add a member" do
          adsi_group.expects(:Add).with("WinNT://S-1-5-18")

          group.add_member_sids(system)
        end

        it "and raise when passed a non-SID object to add" do
          expect{ group.add_member_sids(invalid)}.to raise_error(Puppet::Error, /Must use a valid SID object/)
        end

        it "to remove a member" do
          adsi_group.expects(:Remove).with("WinNT://S-1-5-18")

          group.remove_member_sids(system)
        end

        it "and raise when passed a non-SID object to remove" do
          expect{ group.remove_member_sids(invalid)}.to raise_error(Puppet::Error, /Must use a valid SID object/)
        end
      end

      it "should provide its groups as a list of names" do
        names = ['user1', 'user2']

        users = names.map { |name| double('user', :Name => name) }

        adsi_group.expects(:Members).returns(users)

        expect(group.members).to match(names)
      end

      it "should be able to add a list of users to a group" do
        names = ['DOMAIN\user1', 'user2']
        sids = [
          double(:account => 'user1', :domain => 'DOMAIN'),
          double(:account => 'user2', :domain => 'testcomputername'),
          double(:account => 'user3', :domain => 'DOMAIN2'),
        ]

        # use stubbed objectSid on member to return stubbed SID
        Puppet::Util::Windows::SID.expects(:octet_string_to_sid_object).with([0]).returns(sids[0])
        Puppet::Util::Windows::SID.expects(:octet_string_to_sid_object).with([1]).returns(sids[1])

        Puppet::Util::Windows::SID.expects(:name_to_sid_object).with('user2').returns(sids[1])
        Puppet::Util::Windows::SID.expects(:name_to_sid_object).with('DOMAIN2\user3').returns(sids[2])

        Puppet::Util::Windows::ADSI.expects(:sid_uri).with(sids[0]).returns("WinNT://DOMAIN/user1,user")
        Puppet::Util::Windows::ADSI.expects(:sid_uri).with(sids[2]).returns("WinNT://DOMAIN2/user3,user")

        members = names.each_with_index.map{|n,i| double(:Name => n, :objectSID => [i])}
        adsi_group.expects(:Members).returns members

        adsi_group.expects(:Remove).with('WinNT://DOMAIN/user1,user')
        adsi_group.expects(:Add).with('WinNT://DOMAIN2/user3,user')

        group.set_members(['user2', 'DOMAIN2\user3'])
      end

      it "should raise an error when a username does not resolve to a SID" do
        expect {
          adsi_group.expects(:Members).returns []
          group.set_members(['foobar'])
        }.to raise_error(Puppet::Error, /Could not resolve username: foobar/)
      end

      it "should generate the correct URI" do
        Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
        expect(group.uri).to eq("WinNT://./#{groupname},group")
      end
    end

    it "should generate the correct URI" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      expect(Puppet::Util::Windows::ADSI::Group.uri("people")).to eq("WinNT://./people,group")
    end

    it "should be able to create a group" do
      adsi_group = double("adsi")

      connection.expects(:Create).with('group', groupname).returns(adsi_group)
      Puppet::Util::Windows::ADSI::User.expects(:exists?).with(groupname).returns(false)

      group = Puppet::Util::Windows::ADSI::Group.create(groupname)

      expect(group).to be_a(Puppet::Util::Windows::ADSI::Group)
      expect(group.native_group).to eq(adsi_group)
    end

    it "should be able to confirm the existence of a group" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)
      Puppet::Util::Windows::ADSI.expects(:connect).with("WinNT://./#{groupname},group").returns connection

      expect(Puppet::Util::Windows::ADSI::Group.exists?(groupname)).to be_truthy
    end

    it "should be able to confirm the existence of a group with a well-known SID" do

      service_group = Win32::Security::SID::Service
      # ensure that the underlying OS is queried here
      allow(Puppet::Util::Windows::ADSI).to receive(:connect).and_call_original
      expect(Puppet::Util::Windows::ADSI::Group.exists?(service_group)).to be_truthy
    end

    it "should return nil with an unknown SID" do

      bogus_sid = 'S-1-2-3-4'
      # ensure that the underlying OS is queried here
      allow(Puppet::Util::Windows::ADSI).to receive(:connect).and_call_original
      expect(Puppet::Util::Windows::ADSI::Group.exists?(bogus_sid)).to be_falsey
    end

    it "should be able to delete a group" do
      connection.expects(:Delete).with('group', groupname)

      Puppet::Util::Windows::ADSI::Group.delete(groupname)
    end

    it "should return an enumeration of IADsGroup wrapped objects" do
      Puppet::Util::Windows::ADSI.stubs(:sid_uri_safe).returns(nil)

      name = 'Administrators'
      wmi_groups = [double('WMI', :name => name)]
      Puppet::Util::Windows::ADSI.expects(:execquery).with('select name from win32_group where localaccount = "TRUE"').returns(wmi_groups)

      native_group = double('IADsGroup')
      native_group.expects(:Members).returns([double(:Name => 'Administrator')])
      Puppet::Util::Windows::ADSI.expects(:connect).with("WinNT://./#{name},group").returns(native_group)

      groups = Puppet::Util::Windows::ADSI::Group.to_a
      expect(groups.length).to eq(1)
      expect(groups[0].name).to eq(name)
      expect(groups[0].members).to eq(['Administrator'])
    end
  end

  describe Puppet::Util::Windows::ADSI::UserProfile do
    it "should be able to delete a user profile" do
      connection.expects(:Delete).with("Win32_UserProfile.SID='S-A-B-C'")
      Puppet::Util::Windows::ADSI::UserProfile.delete('S-A-B-C')
    end

    it "should warn on 2003" do
      connection.expects(:Delete).raises(RuntimeError,
 "Delete (WIN32OLERuntimeError)
    OLE error code:80041010 in SWbemServicesEx
      Invalid class
    HRESULT error code:0x80020009
      Exception occurred.")

      Puppet.expects(:warning).with("Cannot delete user profile for 'S-A-B-C' prior to Vista SP1")
      Puppet::Util::Windows::ADSI::UserProfile.delete('S-A-B-C')
    end
  end
end
