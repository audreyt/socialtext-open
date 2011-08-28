#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Group::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 18;

# Force any LDAP Group lookups to be synchronous.
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
# Fixtures
fixtures(qw( db ));

###############################################################################
# Helpers
my $DefaultAcct = Socialtext::Account->Default;
my $SystemUser  = Socialtext::User->SystemUser;
my $MemberRole  = Socialtext::Role->Member;
my $AdminRole   = Socialtext::Role->Admin;
my $GroupDN     = 'cn=Motorhead,dc=example,dc=com';

###############################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),  'added people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), 'added groups';
    return $openldap;
}

###############################################################################
# TEST: Default Group
default_group_has_initial_relationships: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    my $group = Socialtext::Group->Create( {
        driver_group_name  => 'Test Group',
        created_by_user_id => $user->user_id,
    } );
    isa_ok $group, 'Socialtext::Group';
    isa_ok $group->homunculus, 'Socialtext::Group::Default';

    # Default Groups are created in the "Default Account" unless explicitly
    # specified.
    is $group->primary_account->name, $DefaultAcct->name,
        '... created in creators Primary Account';
    ok $DefaultAcct->has_group($group),
        '... ... Account knows that the Group has a Role in it';
    is $DefaultAcct->role_for_group($group)->name, $MemberRole->name,
        '... ... the "Member" Role';

    # Default Groups have an actual creator, who is given the "Admin" Role in
    # the Group.
    is $group->creator->username, $user->username,
        '... created by the specified User';
    ok $group->has_user($user),
        '... ... who has a Role in the Group';
    is $group->role_for_user($user)->name, $AdminRole->name,
        '... ... the "Admin" Role';
}

###############################################################################
# TEST: LDAP Group
ldap_group_has_initial_relationships: {
    my $openldap = bootstrap_openldap();
    my $group    = Socialtext::Group->GetGroup(driver_unique_id => $GroupDN);
    isa_ok $group, 'Socialtext::Group';
    isa_ok $group->homunculus, 'Socialtext::Group::LDAP';

    # LDAP Groups get created in the "Default Account", with the "Member" Role
    is $group->primary_account->name, $DefaultAcct->name,
        '... created in the Default Account';
    ok $DefaultAcct->has_group($group),
        '... ... Account knows that the Group has a Role in it';
    is $DefaultAcct->role_for_group($group)->name, $MemberRole->name,
        '... ... the "Member" Role';

    # LDAP Groups are created by the "System User", who *doesn't* get a Role
    # in the Group (cuz he's a system-user)
    is $group->creator->username, $SystemUser->username,
        '... created by the System User';
    ok !$group->has_user($SystemUser),
        '... ... who has no Role in the Group';
}







