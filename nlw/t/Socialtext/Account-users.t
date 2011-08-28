#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 23;
use Socialtext::Role;
use Test::Socialtext::Fatal;

###############################################################################
# Fixtures: db
# - Need a DB, but don't care what's in it
fixtures(qw( db ));

my $Member = Socialtext::Role->Member();
my $Admin  = Socialtext::Role->Admin();

###############################################################################
# TEST: a newly created Account has *no* Users in it
new_account_has_no_users: {
    my $account = create_test_account_bypassing_factory();
    my $count   = $account->user_count();
    is $count, 0, 'newly created Account has no Users in it';

    # Query the list of Users in the Account, make sure count matches
    #
    # NOTE: actual Users returned is tested in t/ST/Users-ByAccountId.t
    my $cursor = $account->users();
    isa_ok $cursor, 'Socialtext::MultiCursor', 'User cursor';
    is $cursor->count(), 0, '... with no Users in it';

    my $ids = $account->user_ids();
    is scalar(@{$ids}), 0, '... with no User Ids in it';
}

###############################################################################
# TEST: User count is correct
user_count_is_correct: {
    my $account = create_test_account_bypassing_factory();
    my $ws      = create_test_workspace(account => $account);
    my $group   = create_test_group();
    $ws->add_group(group => $group);

    # user: primary account
    my $user = create_test_user(account => $account);

    # user: secondary account, via UWR in WS
    $user = create_test_user();
    $ws->add_user(user => $user);

    my $count = $account->user_count();
    is $count, 2, 'Account has two Users';

    my $cursor = $account->users();
    isa_ok $cursor, 'Socialtext::MultiCursor', 'User cursor';
    is $cursor->count(), 2, '... with two Users in it';

    my $ids = $account->user_ids();
    is scalar(@{$ids}), 2, '... with two User Ids in it';

# XXX: YANK this out, we're not explicitly recording groups memberships right now.
#     # user: secondary account, via UGR+GWR in WS
#     $user = create_test_user();
#     $group->add_user(user => $user);
# 
#     # Query user count
#     my $count = $account->user_count();
#     is $count, 3, 'Account has three Users';
# 
#     # Query the list of Users in the Account, make sure count matches
#     #
#     # NOTE: actual Users returned is tested in t/ST/Users-ByAccountId.t
#     my $cursor = $account->users();
#     isa_ok $cursor, 'Socialtext::MultiCursor', 'User cursor';
#     is $cursor->count(), 3, '... with three Users in it';
# 
#     my $ids = $account->user_ids();
#     is scalar(@{$ids}), 3, '... with three User Ids in it';
}

###############################################################################
# TEST: Add User to Account with default Role.
add_user_to_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    $account->add_user(user => $user);

    my $result = $account->role_for_user($user);
    is $result->name, 'member', '... with correct role';
}

###############################################################################
# TEST: Add User to Account with explicit Role.
add_user_to_account_explicit_role: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    $account->add_user(user => $user, role => $Admin);

    my $result = $account->role_for_user($user);
    is $result->name, $Admin->name, '... with correct role';
}

###############################################################################
# TEST: Check of User has a Role in an Account.
user_has_role_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    ok !$account->has_user($user), 'User does not yet have Role in Account';
    $account->add_user(user => $user);
    ok $account->has_user($user), '... User has been added to Account';
}

###############################################################################
# TEST: Role For User - User's Primary Account
role_for_user_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    my $q_role = $account->role_for_user($user);
    is $q_role->name, $Member->name, 'User has Member Role in Primary Account';
}

###############################################################################
# TEST: Role For User - Explicitly assigned Role
role_for_user_explicit_role: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    $account->add_user(user => $user, role => $Admin);

    my $q_role = $account->role_for_user($user);
    is $q_role->name, $Admin->name, 'User has assigned Role in Account';
}

###############################################################################
# TEST: Role For User - indirect Role through Workspace membership
role_for_user_indirect_via_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $user      = create_test_user();

    $workspace->add_user(user => $user, role => $Admin);

    my $q_role = $account->role_for_user($user);
    is $q_role->name, $Member->name,
        'User has member Role, via Workspace membership, not admin';
}

###############################################################################
# TEST: Role For User - indirect Role through Group membership
role_for_user_indirect_via_group: {
    my $account   = create_test_account_bypassing_factory();
    my $group     = create_test_group(account => $account);
    my $user      = create_test_user();

    $group->add_user(user => $user, role => $Admin);

    my $q_role = $account->role_for_user($user);
    is $q_role->name, $Member->name,
        'User has Member Role, via Group membership, not admin';
}

###############################################################################
# TEST: Role For User - indirect Role through Group->Workspace membership
role_for_user_indirect_via_group_in_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user      = create_test_user();

    $workspace->add_group(group => $group, role => $Admin);
    $group->add_user(user => $user, role => $Admin);

    my $q_role = $account->role_for_user($user);
    is $q_role->name, $Member->name,
        'User has member Role, via Group in Workspace membership, not admin';
}

###############################################################################
# TEST: Remove User from Account.
remove_user_from_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    # Account should not (yet) have this User
    ok !$account->has_user($user), 'User does not yet have Role in Account';

    # Add the User to the Account
    $account->add_user(user => $user);
    ok $account->has_user($user), '... User has been added to Account';

    # Remove the User from the Account
    $account->remove_user(user => $user);
    ok !$account->has_user($user), '... User has been removed from Account';
}

###############################################################################
# TEST: Cannot remove User from their Primary Account.
cant_remove_user_from_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    # Account should already have this User
    ok $account->has_user($user), 'User has Role in his Primary Account';

    # Can't remove the User from his Primary Account
    like exception { $account->remove_user(user => $user) },
        qr/Cannot remove a user from their primary account/;
    ok $account->has_user($user), '... User maintains Role in Primary Account';
}

###############################################################################
# XXX: This test is invalid untill we start explicitly adding group roles.
# TEST: User count is de-duped
# user_count_is_deduped: {
#     my $account = create_test_account_bypassing_factory();
#     my $ws      = create_test_workspace(account => $account);
#     my $group   = create_test_group();
#     $ws->add_group(group => $group);
# 
#     # user: primary account, plus UWR and UGR+GWR
#     my $user = create_test_user(account => $account);
#     $ws->add_user(user => $user);
#     $group->add_user(user => $user);
# 
#     # user: secondary account *only*, UWR and UGR+GWR
#     $user = create_test_user();
#     $ws->add_user(user => $user);
#     $group->add_user(user => $user);
# 
#     # Query user count
#     my $count = $account->user_count();
#     is $count, 2, 'Account has two Users';
# 
#     # Query the list of Users in the Account, make sure count matches
#     #
#     # NOTE: actual Users returned is tested in t/ST/Users-ByAccountId.t
#     my $cursor = $account->users();
#     isa_ok $cursor, 'Socialtext::MultiCursor', 'User cursor';
#     is $cursor->count(), 2, '... with two Users in it';
# 
#     my $ids = $account->user_ids();
#     is scalar(@{$ids}), 2, '... with two User Ids in it';
# }
