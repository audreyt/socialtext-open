#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 17;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User;
use Socialtext::Role;

fixtures(qw( db ));

###############################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'),
        '.. added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),
        '... added data: people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'),
        '... added data: groups';
    return $openldap;
}


my $account = create_test_account_bypassing_factory();
ok $account, 'made test account';
set_as_default_account($account);
is(Socialtext::Account->Default->account_id, $account->account_id,
    'configured default account');

###############################################################################
user_vivified_into_all_users_workspace: {
    my $openldap = bootstrap_openldap();
    my $ws       = create_test_workspace(account => $account);
    my $member   = Socialtext::Role->Member();

    # Setup
    $ws->add_account(account => $account);
    is_deeply [map { $_->name } @{$account->all_users_workspaces || []}],
        [$ws->name], 'set up all-users workspace';

    # First, a "Default" User (so we know it works)
    my $user = create_test_user(account => $account);
    isa_ok $user, 'Socialtext::User', 'test Default User';
    isa_ok $user->homunculus, 'Socialtext::User::Default', '... a Default User';

    is $user->primary_account_id, $account->account_id,
        '... User has correct Primary Account';

    my $role = $ws->role_for_user($user);
    ok $role, '... User has Role in All Users Workspace';
    is $role->name, $member->name, '... ... the Member role';

    # Then, do it with an "LDAP" User (so we know it works for LDAP Users)
    $user = Socialtext::User->new(
        email_address => 'ray.parker@example.com',
    );
    isa_ok $user, 'Socialtext::User', 'test LDAP User';
    isa_ok $user->homunculus, 'Socialtext::User::LDAP', '... an LDAP User';

    is $user->primary_account_id, $account->account_id,
        '... User has correct Primary Account';

    $role = $ws->role_for_user($user);
    ok $role, '... User has Role in All Users Workspace';
    is $role->name, $member->name, '... ... the Member role';
}
