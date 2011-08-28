#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 39;
use Test::Socialtext::Fatal;
use Test::Warn;

use Socialtext::User;
use Socialtext::Role;

################################################################################
# Fixtures: db
# - Need a DB around, but don't care what's in it
fixtures(qw( db ));

use_ok 'Socialtext::Account';

deprecated: {
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace(account => $acct);
    ok exception {
        $acct->update(all_users_workspace => $ws->workspace_id);
    }, 'updating an account with an AUW is deprecated';
}

################################################################################
# TEST: Set all_users_workspace
set_all_users_workspace: {
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace(account => $acct);

    $ws->add_account( account => $acct );

    ok $ws->is_all_users_workspace, "workspace is AUW";
    ok $acct->has_all_users_workspaces, 'account has AUWs';
}

################################################################################
# TEST: Set all_users_workspace, workspace not in account
set_workspace_not_in_account: {
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace();

    ok exception {
        $ws->add_account(account => $acct);
    }, 'dies when workspace is not in account';

    ok !$acct->has_all_users_workspaces, '... all users workspace not updated';
}

################################################################################
# TEST: Add user to account no all users workspace.
account_no_workspace: {
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace(account => $acct);
    my $user = create_test_user(account => $acct);

    my $ws_users = $ws->users;
    isa_ok $ws_users, 'Socialtext::MultiCursor';
    is $ws_users->count, 0, '... with no users';
}

################################################################################
# TEST: Add/Remove user to account with all users workspace ( high level ).
account_with_workspace_high_level: {
    my $other_acct = create_test_account_bypassing_factory();
    my $acct       = create_test_account_bypassing_factory();
    my $ws         = create_test_workspace(account => $acct);

    $ws->add_account(account => $acct);

    my $user = create_test_user( account => $acct );

    my $ws_users = $ws->users;
    isa_ok $ws_users, 'Socialtext::MultiCursor';
    is $ws_users->count, 1, '... with one user';
    
    my $ws_user = $ws_users->next();
    is $ws_user->username, $user->username, '... who is the correct user';

    # Change user's primary account
    $user->primary_account( $other_acct );
    $acct->remove_user(user => $user);

    $ws_users = $ws->users;
    isa_ok $ws_users, 'Socialtext::MultiCursor';
    is $ws_users->count, 0, '... and now the user is gone';
}

################################################################################
# TEST: user is added when all users workspace changes
account_with_workspace_high_level: {
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace(account => $acct);
    my $user = create_test_user(account => $acct);

    $ws->add_account( account => $acct );

    my $ws_users = $ws->users;
    isa_ok $ws_users, 'Socialtext::MultiCursor';
    is $ws_users->count, 1, '... with one user';
}

################################################################################
user_primary_account_change: {
    my $old_acct = create_test_account_bypassing_factory();
    my $old_ws   = create_test_workspace(account => $old_acct);
    my $new_acct = create_test_account_bypassing_factory();
    my $new_ws   = create_test_workspace(account => $new_acct);
    my $member   = Socialtext::Role->Member();

    $old_ws->add_account(account => $old_acct);
    $new_ws->add_account(account => $new_acct);

    my $user = create_test_user( account => $old_acct );

    # make sure User is in all users Workspace
    my $role = $old_ws->role_for_user($user);
    ok $role, 'User has Role in old all users Workspace';
    is $role->role_id, $member->role_id, '... Role is member';

    # Update the User's primary Account
    $user->primary_account( $new_acct );
    is $user->primary_account_id, $new_acct->account_id,
       'User is in new primary Account';

    # make sure User is in new all users Workspace
    $role = $new_ws->role_for_user($user);
    ok $role, 'User has Role in new all users Workspace';
    is $role->role_id, $member->role_id, '... Role is member';

    # make sure User is still in the _old_ all users Workspace
    $role = $old_ws->role_for_user($user);
    ok $role, 'User still has Role in old all users Workspace';
    is $role->role_id, $member->role_id, '... Role is member';
}

################################################################################
user_with_indirect_account_role: {
    my $user   = create_test_user();
    my $acct   = create_test_account_bypassing_factory();
    my $auw    = create_test_workspace(account => $acct);
    my $ws     = create_test_workspace(account => $acct);
    my $member = Socialtext::Role->Member();

    $auw->add_account(account => $acct);

    # Give user an indirect role in the Account by adding them to a (non-AUW)
    # workspace
    $ws->add_user( user => $user, role => $member );

    # Verify the the User has a Role in the Account
    my $role = $acct->role_for_user($user);
    ok $role, 'User has Role in Account';

    # User was also added to all users Workspace
    $role = $auw->role_for_user($user);
    ok $role, 'User has Role in all users Workspace';
    is $role->role_id, $member->role_id, '... Role is member';
}

################################################################################
group_has_role_in_auw_exists: {
    my $acct   = create_test_account_bypassing_factory();
    my $ws     = create_test_workspace(account => $acct);
    my $group  = create_test_group(account => $acct);
    my $user   = create_test_user();
    my $member = Socialtext::Role->Member();

    # Update AUW _before_ adding the group.
    $ws->add_account(account => $acct);

    # Add User to Group
    $group->add_user( user => $user );
    my $role = $group->role_for_user($user);
    ok $role, 'User has Role in Group';
    is $role->role_id, $member->role_id, '... Role is Member';

    # Check User's Role in the AUW
    $role = $ws->role_for_user($user, direct => 1 );
    ok !$role, 'User does _not_ have a direct Role in AUW';

    $role = $ws->role_for_user($user);
    ok $role, 'User has an indirect Role in AUW';
}

################################################################################
group_has_role_in_auw_updated: {
    my $acct   = create_test_account_bypassing_factory();
    my $ws     = create_test_workspace(account => $acct);
    my $group  = create_test_group(account => $acct);
    my $user   = create_test_user();
    my $member = Socialtext::Role->Member();

    # Add User to Group
    $group->add_user( user => $user );
    my $role = $group->role_for_user($user);
    ok $role, 'User has Role in Group';
    is $role->role_id, $member->role_id, '... Role is Member';

    $ws->add_account(account => $acct);

    # Check User's Role in the AUW
    $role = $ws->role_for_user($user, direct => 1 );
    ok !$role, 'User does _not_ have a direct Role in AUW';

    $role = $ws->role_for_user($user);
    ok $role, 'User has an indirect Role in AUW';
}

################################################################################
group_has_role_in_auw_when_added_to_account: {
    my $acct   = create_test_account_bypassing_factory();
    my $ws     = create_test_workspace(account => $acct);
    my $group  = create_test_group();
    my $user   = create_test_user();
    my $member = Socialtext::Role->Member();

    $ws->add_account(account => $acct);

    # Add User to Group
    $group->add_user( user => $user );
    my $role = $group->role_for_user($user);
    ok $role, 'User has Role in Group';
    is $role->role_id, $member->role_id, '... Role is Member';

    # Add Group to Account
    $acct->add_group( group => $group );
    ok $acct->has_group( $group ), 'Group is added to Account';
    ok $acct->has_user( $user ), 'User is added to Account';

    # Check User's Role in the AUW
    $role = $ws->role_for_user($user, direct => 1 );
    ok !$role, 'User does _not_ have a direct Role in AUW';

    $role = $ws->role_for_user($user);
    ok $role, 'User has an indirect Role in AUW';
}
