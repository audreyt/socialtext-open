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

###############################################################################
# TEST: Group has a "Member" Role in its Primary Account.
groups_role_in_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group(account => $account);

    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in Primary Account';
}

###############################################################################
# TEST: Group has an "Member" Role in any secondary Account that it happens
# to have a Workspace membership in.
groups_role_in_secondary_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();

    $ws->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in Secondary Accounts';
}

###############################################################################
# TEST: Group is explicitly a "Member" in an Account.  Adding the Group to a
# WS in that Account does not overwrite their "Member" Role.
no_overwrite_of_member_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();

    $account->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in test Account';

    $ws->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        '... added Group to WS in Account; Role in Account unchanged';
}

###############################################################################
# TEST: Group is explicitly a "Member" in an Account.  Removing the Group from
# a WS in that Account does not overwrite/remove their "Member" Role.
no_teardown_of_member_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();

    $account->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in test Account';

    $ws->add_group(group => $group);
    ok $ws->has_group($group), '... added Group to WS';
    is $account->role_for_group($group)->name, $Member->name,
        '... ... Role in its Account is unchanged';

    $ws->remove_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        '... Group removed from WS; Role in Account unchanged';
}

###############################################################################
# TEST: Group is "Member" of a WS, giving them an Member Role in the WS's
# Account.  Adding the Group to that Account upgrades their GAR to "Member".
role_upgrade: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();

    $ws->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in secondary Account';

    $account->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        '... adding Group to Account upgrades to Member Role';
}

###############################################################################
# TEST: Group is "Member" of a WS _and_ its Account.  Removing the Group from
# the Account downgrades its "Member" Role to "Member" (because the Group
# still has a Role in the Workspace).
role_downgrade: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();

    $ws->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        'Group has Member Role in secondary Account';

    $account->add_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        '... adding Group to Account upgrades to Member Role';

    $account->remove_group(group => $group);
    is $account->role_for_group($group)->name, $Member->name,
        '... removing Group from Account downgrades to Member Role';
}
