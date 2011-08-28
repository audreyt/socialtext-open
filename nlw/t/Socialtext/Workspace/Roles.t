#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 49;
use Test::Differences;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it
fixtures(qw( db ));

use_ok 'Socialtext::Workspace::Roles';
use_ok 'Socialtext::Role';

###############################################################################
# TEST: Get Users with a Role in a given Workspace
users_by_workspace_id: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $user_one    = create_test_user();
    my $user_two    = create_test_user();
    my $group       = create_test_group();

    # One of the Users has an explicit Role in the Workspace
    $workspace->add_user(user => $user_one);

    # Another User has a Role in the Workspace via Group membership
    $group->add_user(user => $user_two);
    $workspace->add_group(group => $group);

    # Get the list of Users in the Workspace
    my $cursor = Socialtext::Workspace::Roles->UsersByWorkspaceId(
        workspace_id => $workspace->workspace_id,
    );
    isa_ok $cursor, 'Socialtext::MultiCursor', 'list of Users in WS';
    is $cursor->count(), 2, '... with correct number of Users';

    is $cursor->next->user_id, $user_one->user_id,
        '... ... first expected test User';
    is $cursor->next->user_id, $user_two->user_id,
        '... ... second expected test User';

    # Test for UserHasRoleInWorkspace
    for my $user ($user_one, $user_two) {
        ok(Socialtext::Workspace::Roles->UserHasRoleInWorkspace(
            user      => $user_one,
            role      => Socialtext::Role->Member,
            workspace => $workspace
        ), "UserHasRoleInWorkspace returns true for " . $user->best_full_name);
    }

    # Unrelated workspaces shouldn't affect UserHasRoleInWorkspace -- {bz: 2862}
    my $yet_another_workspace = create_test_workspace(user => $system_user);
    my $yet_another_user_one  = create_test_user();
    my $yet_another_user_two  = create_test_user();
    my $yet_another_group     = create_test_group();

    $yet_another_group->add_user(user => $yet_another_user_two);
    $yet_another_workspace->add_group(group => $yet_another_group);

    for my $yet_another_user ($yet_another_user_one, $yet_another_user_two) {
        ok(!Socialtext::Workspace::Roles->UserHasRoleInWorkspace(
            user      => $yet_another_user,
            role      => Socialtext::Role->Member,
            workspace => $workspace
        ), "UserHasRoleInWorkspace returns false for " . $yet_another_user->best_full_name);
    }
}

###############################################################################
# TEST: Get Users with a Role in a given Workspace, when a User has _multiple_
# *different* Roles in the WS
users_by_workspace_id_multiple_group_roles: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $user        = create_test_user();
    my $group_one   = create_test_group();
    my $group_two   = create_test_group();
    my $role_member = Socialtext::Role->Member;
    my $role_admin  = Socialtext::Role->Admin;

    # User has multiple Roles in the WS via Group memberships
    $group_one->add_user(user => $user);
    $workspace->add_group(group => $group_one, role => $role_member);

    $group_two->add_user(user => $user);
    $workspace->add_group(group => $group_two, role => $role_admin);

    # Get the list of Users in the Workspace
    my $cursor = Socialtext::Workspace::Roles->UsersByWorkspaceId(
        workspace_id => $workspace->workspace_id,
    );
    isa_ok $cursor, 'Socialtext::MultiCursor', 'list of Users in WS';
    is $cursor->count(), 1, '... User only appears *ONCE* in the list';
    is $cursor->next->user_id, $user->user_id, '... ... expected test User';
}

###############################################################################
# TEST: Count Users with a Role in a given Workspace
count_users_by_workspace_id: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $user_one    = create_test_user();
    my $user_two    = create_test_user();
    my $group       = create_test_group();

    # One of the Users has an explicit Role in the Workspace
    $workspace->add_user(user => $user_one);

    # Another User has a Role in the Workspace via Group membership
    $group->add_user(user => $user_two);
    $workspace->add_group(group => $group);

    # Get the count of Users in the Workspace
    my $count = Socialtext::Workspace::Roles->CountUsersByWorkspaceId(
        workspace_id => $workspace->workspace_id,
    );
    is $count, 2, 'WS has correct number of Users';
}

###############################################################################
# TEST: Get Users with a Role in a given Workspace, when a User has _multiple_
# Roles in the WS
count_users_by_workspace_id_multiple_group_roles: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $user        = create_test_user();
    my $group_one   = create_test_group();
    my $group_two   = create_test_group();

    # User has multiple Roles in the WS via Group memberships
    $group_one->add_user(user => $user);
    $workspace->add_group(group => $group_one);

    $group_two->add_user(user => $user);
    $workspace->add_group(group => $group_two);

    # Get the count of Users in the Workspace
    my $count = Socialtext::Workspace::Roles->CountUsersByWorkspaceId(
        workspace_id => $workspace->workspace_id,
    );
    is $count, 1, 'WS has correct number of Users';
}

###############################################################################
# TEST: User has a specific Role in the WS.
user_has_role: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $role_admin  = Socialtext::Role->Admin();
    my $role_member = Socialtext::Role->Member();
    my $role_guest  = Socialtext::Role->Guest();
    my $rc;

    # User has explicit UWR
    user_has_role_explicit_uwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_admin);

        $rc = $workspace->user_has_role(user => $user, role => $role_admin);
        ok $rc, 'User with explicit UWR has specific Role in WS';

        $rc = $workspace->user_has_role(user => $user, role => $role_guest);
        ok !$rc, 'User does not have this Role in WS';
    }

    # User has UWR+GWR
    user_has_role_uwr_and_gwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_admin);

        my $group = create_test_group();
        $group->add_user(user => $user);
        $workspace->add_group(group => $group, role => $role_member);

        $rc = $workspace->user_has_role(user => $user, role => $role_admin);
        ok $rc, 'User has UWR Role in WS';
        
        $rc = $workspace->user_has_role(user => $user, role => $role_member);
        ok $rc, 'User has GWR Role in WS';

        $rc = $workspace->user_has_role(user => $user, role => $role_guest);
        ok !$rc, 'User does not have this Role in WS';
    }

    # User has multiple GWRs
    user_has_role_multiple_gwrs: {
        my $user      = create_test_user();
        my $group_one = create_test_group();
        my $group_two = create_test_group();

        $group_one->add_user(user => $user);
        $workspace->add_group(group => $group_one, role => $role_admin);

        $group_two->add_user(user => $user);
        $workspace->add_group(group => $group_two, role => $role_member);

        $rc = $workspace->user_has_role(user => $user, role => $role_admin);
        ok $rc, 'User has GWR Role in WS';
        
        $rc = $workspace->user_has_role(user => $user, role => $role_member);
        ok $rc, 'User has alternate GWR Role in WS';

        $rc = $workspace->user_has_role(user => $user, role => $role_guest);
        ok !$rc, 'User does not have this Role in WS';
    }
}

###############################################################################
# TEST: Get the list of Roles for a User in the Workspace.
get_roles_for_user_in_workspace: {
    my $system_user = Socialtext::User->SystemUser();
    my $workspace   = create_test_workspace(user => $system_user);
    my $role_admin  = Socialtext::Role->Admin();
    my $role_member = Socialtext::Role->Member();
    my $role_guest  = Socialtext::Role->Guest();

    get_roles_for_user_explicit_uwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_admin);

        my $role = Socialtext::Workspace::Roles->RolesForUserInWorkspace(
            user      => $user,
            workspace => $workspace,
        );
        isa_ok $role, 'Socialtext::Role', 'Users Role in WS';
        is $role->role_id(), $role_admin->role_id(),
            '... is the assigned Role';
    }

    get_roles_for_user_uwr_and_gwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_admin);

        my $group = create_test_group();
        $group->add_user(user => $user);
        $workspace->add_group(group => $group, role => $role_member);

        # SCALAR: highest effective Role
        my $role = Socialtext::Workspace::Roles->RolesForUserInWorkspace(
            user      => $user,
            workspace => $workspace,
        );
        is $role->role_id, $role_admin->role_id,
            'Users highest effective Role in the WS';

        # LIST: all Roles, ordered from highest->lowest
        my @roles = Socialtext::Workspace::Roles->RolesForUserInWorkspace(
            user      => $user,
            workspace => $workspace,
        );
        is scalar @roles, 2, 'User has multiple Roles in the WS';
        is $roles[0]->role_id, $role_admin->role_id,
            '... first Role has higher effectiveness';
        is $roles[1]->role_id, $role_member->role_id,
            '... second Role has lower effectiveness';
    }

    get_roles_for_user_multiple_gwrs: {
        my $user      = create_test_user();
        my $group_one = create_test_group();
        my $group_two = create_test_group();

        $group_one->add_user(user => $user);
        $workspace->add_group(group => $group_one, role => $role_member);

        $group_two->add_user(user => $user);
        $workspace->add_group(group => $group_two, role => $role_admin);

        # SCALAR: highest effective Role
        my $role = Socialtext::Workspace::Roles->RolesForUserInWorkspace(
            user      => $user,
            workspace => $workspace,
        );
        is $role->role_id, $role_admin->role_id,
            'Users highest effective Role in the WS';

        # LIST: all Roles, ordered from highest->lowest
        my @roles = Socialtext::Workspace::Roles->RolesForUserInWorkspace(
            user      => $user,
            workspace => $workspace,
        );
        is scalar @roles, 2, 'User has multiple Roles in the WS';
        is $roles[0]->role_id, $role_admin->role_id,
            '... first Role has higher effectiveness';
        is $roles[1]->role_id, $role_member->role_id,
            '... second Role has lower effectiveness';
    }
}

###############################################################################
# TEST: Get Workspaces that a given User has a Role in
workspaces_by_user_id: {
    my $user = create_test_user();

    my $ws_one   = create_test_workspace(unique_id => 'workspace_c');
    my $ws_two   = create_test_workspace(unique_id => 'workspace_f');
    my $ws_three = create_test_workspace(unique_id => 'workspace_a');

    # User has access via explicit Role in the Workspace
    $ws_one->add_user(user => $user);

    # User has access via Group Role in the Workspace
    my $group = create_test_group();
    $group->add_user(user => $user);
    $ws_two->add_group(group => $group);

    # User has access via UWR and multiple UGR+GWRs
    $ws_three->add_user(user => $user);

    $group = create_test_group();
    $group->add_user(user => $user);
    $ws_three->add_group(group => $group);

    $group = create_test_group();
    $group->add_user(user => $user);
    $ws_three->add_group(group => $group);

    # Get list of Workspaces the User has access to
    ws_by_user_id_default_order: {
        my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
            user_id => $user->user_id,
        );
        isa_ok $cursor, 'Socialtext::MultiCursor',
            'list of Workspaces that User has access to';
        is $cursor->count(), 3, '... each WS appears *ONCE* in the list';
        eq_or_diff(
            [ map { $_->name } $cursor->all ],
            [ sort map { $_->name } ($ws_one, $ws_two, $ws_three) ],
            '... WS returned ordered by name'
        );
    }

    ws_by_user_id_id_order: {
        my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
            user_id => $user->user_id,
            order_by => 'id',
        );
        isa_ok $cursor, 'Socialtext::MultiCursor',
            'list of Workspaces that User has access to';
        eq_or_diff(
            [ map { $_->workspace_id } $cursor->all ],
            [ sort { $a <=> $b } 
                map { $_->workspace_id } ($ws_one, $ws_two, $ws_three) ],
            '... WS returned ordered by id'
        );
    }

    ws_by_user_id_invalid_order: {
        eval {
            Socialtext::Workspace::Roles->WorkspacesByUserId(
                user_id => $user->user_id,
                order_by => 'JJsksksjK',
            );
        };
        ok($@, 'Invalid order_by throws an exception');
    }

    ws_by_user_id_create_order: {
        my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
            user_id => $user->user_id,
            order_by => 'newest',
        );
        isa_ok $cursor, 'Socialtext::MultiCursor',
            'list of Workspaces that User has access to';
        eq_or_diff(
            [ map { $_->creation_datetime } $cursor->all ],
            [ sort { $b cmp $a } map { $_->creation_datetime } ($ws_one, $ws_two, $ws_three) ],
            '... WS returned ordered by create timestamp'
        );
    }

    # Get list of Workspaces, limited
    ws_by_user_id_limited: {
        my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
            user_id => $user->user_id,
            limit   => 1,
        );
        isa_ok $cursor, 'Socialtext::MultiCursor',
            'list of Workspaces that User has access to';
        is $cursor->count(), 1, '... limited to *one* result';
        is $cursor->next->name, $ws_three->name, '... the first WS by name';
    }

    # Get list of Workspaces, limit + offset
    ws_by_user_id_limit_and_offset: {
        my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
            user_id => $user->user_id,
            limit   => 1,
            offset  => 1,
        );
        isa_ok $cursor, 'Socialtext::MultiCursor',
            'list of Workspaces that User has access to';
        is $cursor->count(), 1, '... limited to *one* result';
        is $cursor->next->name, $ws_one->name, '... the second WS by name';
    }
}

###############################################################################
# TEST: Count Workspaces that a given User has a Role in
count_workspaces_by_user_id: {
    my $user = create_test_user();

    my $ws_one   = create_test_workspace();
    my $ws_two   = create_test_workspace();
    my $ws_three = create_test_workspace();

    # User has access via explicit Role in the Workspace
    $ws_one->add_user(user => $user);

    # User has access via Group Role in the Workspace
    my $group = create_test_group();
    $group->add_user(user => $user);
    $ws_two->add_group(group => $group);

    # User has access via UWR and multiple UGR+GWRs
    $ws_three->add_user(user => $user);

    $group = create_test_group();
    $group->add_user(user => $user);
    $ws_three->add_group(group => $group);

    $group = create_test_group();
    $group->add_user(user => $user);
    $ws_three->add_group(group => $group);

    # Get the count of Workspaces the User has access to
    my $count = Socialtext::Workspace::Roles->CountWorkspacesByUserId(
        user_id => $user->user_id,
    );
    is $count, 3, 'User has access to correct number of Workspaces';

    # Make sure that count matches up with the list of Workspaces
    my $cursor = Socialtext::Workspace::Roles->WorkspacesByUserId(
        user_id => $user->user_id,
    );
    is $count, $cursor->count(), '... matching count of WS access list';
}
