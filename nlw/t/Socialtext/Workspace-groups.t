#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 24;
use Test::Socialtext::Fatal;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it.
fixtures(qw( db ));

use_ok 'Socialtext::Workspace';

################################################################################
# TEST: Workspace and Group have compatible permissions
compatible_permissions: {
    my $ws  = create_test_workspace();
    my $grp = create_test_group();

    $ws->assign_role_to_group(group => $grp);
    is $ws->group_count(), 1, 'private group added to private workspace';
}

################################################################################
# TEST: Workspace and Group have incompatible permissions
incompatible_permissions: {
    my $ws = create_test_workspace();
    my $grp = create_test_group();

    $ws->permissions->set(set_name => 'public-join-to-edit');
    ok exception { $ws->assign_role_to_group(group => $grp); },
        'workspace and group have incompatible permissions';
}

################################################################################
# TEST: Workspace has no Groups with Roles in it
workspace_with_no_groups: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);

    my $groups = $workspace->groups();
    isa_ok $groups, 'Socialtext::MultiCursor', 'got a list of Groups';
    is $groups->count(), 0, '... with the correct count';

    my $count = $workspace->group_count();
    is $count, 0, 'Group count is also correct (zero)';
}

################################################################################
# TEST: Workspace has some Groups with Roles in it
workspace_has_groups: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group_one = create_test_group();
    my $group_two = create_test_group();

    $workspace->add_group(group => $group_one);
    $workspace->add_group(group => $group_two);

    my $groups = $workspace->groups();
    isa_ok $groups, 'Socialtext::MultiCursor', 'got a list of groups';
    is $groups->count(), 2, '... with the correct count';
    isa_ok $groups->next(), 'Socialtext::Group', '... queried Group';

    my $count = $workspace->group_count();
    is $count, 2, 'Group count is also correct (the two Groups we added)';
}

################################################################################
# TEST: Add Group to Workspace with default Role
add_group_to_workspace_with_default_role: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group     = create_test_group();

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);
    is $workspace->group_count(), 1, 'Group was added to Workspace';

    # Make sure Group was given the default Role
    my $default_role = Socialtext::Role->Member;
    my $groups_role  = $workspace->role_for_group($group);
    is $groups_role->role_id, $default_role->role_id,
        '... with Default GWR Role'
}

###############################################################################
# TEST: Add Group to Workspace with explicit Role
add_group_to_workspace_with_role: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group     = create_test_group();
    my $role      = Socialtext::Role->Admin();

    # Add the Group to the Workspace
    $workspace->add_group(group => $group, role => $role);
    is $workspace->group_count(), 1, 'Group was added to Workspace';

    # Make sure Group has the correct Role
    my $groups_role  = $workspace->role_for_group($group);
    is $groups_role->role_id, $role->role_id, '... with provided Role'
}

###############################################################################
# TEST: Update Group's Role in Workspace
update_groups_role_in_workspace: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group     = create_test_group();
    my $role      = Socialtext::Role->Admin();

    # Add the Group to the Workspace, with Default Role
    $workspace->add_group(group => $group);

    # Make sure the Group was given the Default Role
    my $default_role = Socialtext::Role->Member;
    my $groups_role  = $workspace->role_for_group($group);
    is $groups_role->role_id, $default_role->role_id,
        '... with Default UGR Role';

    # Update the Group's Role
    $workspace->assign_role_to_group(group => $group, role => $role);

    # Make sure Group had their Role updated
    $groups_role = $workspace->role_for_group($group);
    is $groups_role->role_id, $role->role_id, '... with updated Role';
}

###############################################################################
# TEST: Get the Role for a Group
get_role_for_group: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group     = create_test_group();

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Get the Role for the Group
    my $role = $workspace->role_for_group($group);
    isa_ok $role, 'Socialtext::Role', 'queried Role';
}

###############################################################################
# TEST: Does this Group have a Role in the Workspace
does_workspace_have_group: {
    my $user      = create_test_user();
    my $workspace = create_test_workspace(user => $user);
    my $group     = create_test_group();

    # Workspace should not (yet) have this Group
    ok !$workspace->has_group($group),
        'Group does not yet have Role in Workspace';

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Now the Group is in the Workspace
    ok $workspace->has_group($group), '... but has now been added';
}

###############################################################################
# TEST: Remove Group from Workspace
remove_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();

    # Workspace should not (yet) have this Group
    ok !$workspace->has_group($group),
        'Group does not yet have Role in Workspace';

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);
    ok $workspace->has_group($group),
        '... Group has been added to Workspace';

    # Remove the Group from the Workspace
    $workspace->remove_group(group => $group);
    ok !$workspace->has_group($group),
        '... Group has been removed from Workspace';
}

###############################################################################
# TEST: Remove Group from Workspace, when the Group has *no* Role in the WS
remove_non_member_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();

    # Workspace should not (yet) have this Group
    ok !$workspace->has_group($group),
        'Group does not yet have Role in Workspace';

    # Removing a non-member Group from the Workspace shouldn't choke.  No
    # errors, no warnings, no fatal exceptions... its basically a no-op.
    ok !exception { $workspace->remove_group(group => $group) },
        "... removing non-member Group from Workspace doesn't choke";
}
