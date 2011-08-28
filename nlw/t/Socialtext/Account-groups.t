#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 20;
use Test::Socialtext::Fatal;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it
fixtures(qw( db ));

###############################################################################
# TEST: a newly created Account has *no* Groups in it.
new_account_has_no_groups: {
    my $account = create_test_account_bypassing_factory();
    my $count   = $account->group_count();
    is $count, 0, 'newly created Account has no Groups in it';

    # query list of Groups in the Account, make sure count matches
    #
    # NOTE: actual Groups returned is tested in t/ST/Groups.t
    my $groups  = $account->groups();
    isa_ok $groups, 'Socialtext::MultiCursor', 'Groups cursor';
    is $groups->count(), 0, '... with no Groups in it';
}

###############################################################################
# TEST: Group count is correct
group_count_is_correct: {
    my $account = create_test_account_bypassing_factory();

    # add some Groups, make sure the count goes up
    my $group_one = create_test_group(account => $account);
    is $account->group_count(), 1, 'Account has one Group';

    my $group_two = create_test_group(account => $account);
    is $account->group_count(), 2, 'Account has two Groups';

    # query list of Groups in the Account, make sure count matches
    #
    # NOTE: actual Groups returned is tested in t/ST/Groups.t
    my $groups = $account->groups();
    is $groups->count(), 2, 'Groups cursor has two Groups in it';
}

###############################################################################
# TEST: Group count is correct, when Groups are removed
group_count_is_correct_when_groups_removed: {
    my $account = create_test_account_bypassing_factory();

    # add some Groups, make sure the count goes up
    my $group_one = create_test_group(account => $account);
    is $account->group_count(), 1, 'Account has one Group';

    my $group_two = create_test_group(account => $account);
    is $account->group_count(), 2, 'Account has two Groups';

    # remove one of the Groups, make sure the count goes down
    $group_two->delete();
    is $account->group_count(), 1, 'Account has only one Group again';
}

###############################################################################
# TEST: Add Group to Account with default Role.
add_group_to_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    $account->add_group( group => $group );

    is $account->group_count(), 1, 'Group was added to Account';
    is $account->role_for_group($group)->name, 'member',
        '... group is a member after add_group()';
}

###############################################################################
# TEST: Add Group to Account with explicit Role.
add_group_to_account_explicit_role: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();
    my $role    = Socialtext::Role->Admin();

    $account->add_group( group => $group, role => $role );

    is $account->group_count(), 1, 'Group was added to Account';
    is $account->role_for_group($group)->name, 'admin',
        '... group is a admin after add_group()';
}

###############################################################################
# TEST: Check if Group has a Role in an Account
group_has_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    ok !$account->has_group($group), 'Group does not yet have Role in Account';
    $account->add_group(group => $group);
    ok  $account->has_group($group), '... Group has been added to Account';
}

###############################################################################
# TEST: Remove Group from Account
remove_group_from_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    # Account should not (yet) have this Group
    ok !$account->has_group($group), 'Group does not yet have Role in Account';

    # Add the Group to the Account
    $account->add_group(group => $group);
    ok $account->has_group($group), '... Group has been added to Account';

    # Remove the Group from the Account
    $account->remove_group(group => $group);
    ok !$account->has_group($group), '... Group has been removed from Account';
}

###############################################################################
# TEST: Remove Group from Account, when the Group has *no* Role in the Account
remove_non_member_group_from_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    # Account should not (yet) have this Group
    ok !$account->has_group($group), 'Group does not yet have Role in Account';

    # Removing a non-member Group from the Account shouldn't choke.  No
    # errors, no warnings, no fatal exceptions... its basically a no-op.
    ok !exception { $account->remove_group(group => $group) },
        "... removing non-member Group from Account doesn't choke";
}
