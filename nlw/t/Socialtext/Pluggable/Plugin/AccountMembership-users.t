#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 13;
use Socialtext::Role;

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# Short-hand names for the Roles we're going to use
my $Member = Socialtext::Role->Member();
my $Admin  = Socialtext::Role->Admin();

###############################################################################
# TEST: User has an "Member" Role in their Primary Account.
users_role_in_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in Primary Account';
}

###############################################################################
# TEST: User has an "Member" Role in any secondary Account that it happens
# to have a Workspace membership in.
users_role_in_secondary_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $user    = create_test_user();

    $ws->add_user(user => $user);
    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in Secondary Accounts';
}

###############################################################################
# TEST: User is explicitly a "Member" in an Account.  Adding the User to a WS
# in that Account does not overwrite their "Member" Role (regardless of what
# Role the User may have had in the WS).
no_overwrite_of_member_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $user    = create_test_user();

    $account->add_user(user => $user, role => $Member);
    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in test Account';

    $ws->add_user(user => $user, role => $Admin);
    is $account->role_for_user($user)->name, $Member->name,
        '... added User to WS in Account; Role in Account unchanged';
}

###############################################################################
# TEST: User is explicitly a "Member" in an Account.  Removing the User from a
# WS in that Account does not overwrite/remove their "Member" Role (regardless
# of what Role the User may have had in the WS).
no_teardown_of_member_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $user    = create_test_user();

    $account->add_user(user => $user, role => $Member);
    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in test Account';

    $ws->add_user(user => $user, role => $Admin);
    ok $ws->has_user($user), '... added User to WS';
    is $account->role_for_user($user)->name, $Member->name,
        '... ... Role in its Account is unchanged';

    $ws->remove_user(user => $user);
    is $account->role_for_user($user)->name, $Member->name,
        '... User removed from WS; Role in Account unchanged';
}

###############################################################################
# TEST: User is "Member" of a WS, giving them an Member Role in the WS's
# Account.  Adding the User to that Account upgrades their UAR to "Member".
role_upgrade: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $user    = create_test_user();

    $ws->add_user(user => $user);
    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in secondary Account';

    $account->add_user(user => $user, role => $Member);
    is $account->role_for_user($user)->name, $Member->name,
        '... adding User to Account upgrades to Member Role';
}

###############################################################################
# TEST: User is "Member" of a WS _and_ its Account.  Removing the User frmo
# the Account downgrades its "Member" Role to "Member" (because the User
# still has a Role in the Workspace).
role_downgrade: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $user    = create_test_user();

    $ws->add_user(user => $user);
    is $account->role_for_user($user)->name, $Member->name,
        'User has Member Role in secondary Account';

    $account->add_user(user => $user, role => $Member);
    is $account->role_for_user($user)->name, $Member->name,
        '... adding User to Account upgrades to Member Role';

    $account->remove_user(user => $user, role => $Member);
    is $account->role_for_user($user)->name, $Member->name,
        '... removing User from Account downgrades to Member Role';
}
