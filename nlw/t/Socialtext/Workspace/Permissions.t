#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Workspace;
use Socialtext::Permission qw(ST_READ_PERM ST_ADMIN_WORKSPACE_PERM);
use Test::Socialtext tests => 6;

###############################################################################
# Fixtures: db
# - Need a DB, don't care what's in it.
fixtures(qw( db ));

###############################################################################
# TEST: See if User has a specific Permission in a "member-only" Workspace
user_has_perm_in_member_only_ws: {
    my $system_user = Socialtext::User->SystemUser();
    my $role_admin  = Socialtext::Role->Admin();
    my $role_member = Socialtext::Role->Member();
    my $workspace   = create_test_workspace(user => $system_user);
    $workspace->permissions->set(set_name => 'member-only');

    user_can_explicit_uwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_member);

        # Perm the User *does* have
        my $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_READ_PERM,
        );
        ok $rc, 'User has read permission';

        # Perm the User *doesn't* have
        $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_ADMIN_WORKSPACE_PERM,
        );
        ok !$rc, 'User does not have admin workspace permission';
    }

    user_can_uwr_and_gwr: {
        my $user = create_test_user();
        $workspace->add_user(user => $user, role => $role_member);

        my $group = create_test_group();
        $group->add_user(user => $user);
        $workspace->add_group(group => $group, role => $role_admin);

        # Perm the User has through GWR
        my $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_ADMIN_WORKSPACE_PERM,
        );
        ok $rc, 'User has permission through Group membership';
    }

    user_can_multiple_gwrs: {
        my $user      = create_test_user();
        my $group_one = create_test_group();
        my $group_two = create_test_group();

        $group_one->add_user(user => $user);
        $workspace->add_group(group => $group_one, role => $role_member);

        $group_two->add_user(user => $user);
        $workspace->add_group(group => $group_two, role => $role_admin);

        # Perm the User has through one of their GWRs
        my $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_ADMIN_WORKSPACE_PERM,
        );
        ok $rc, 'User has permission through Group membership';
    }

    user_can_no_role: {
        my $user = create_test_user();

        # In a "member-only" WS, a non-member User should have *no* Perms
        my $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_READ_PERM,
        );
        ok !$rc, 'User has no Perms when not member in member-only WS';
    }
}

###############################################################################
# TEST: See if User has a specific Permission in a "public" Workspace
user_has_perm_in_public_ws: {
    my $system_user = Socialtext::User->SystemUser();
    my $role_admin  = Socialtext::Role->Admin();
    my $role_member = Socialtext::Role->Member();
    my $workspace   = create_test_workspace(user => $system_user);
    $workspace->permissions->set(set_name => 'public');

    user_can_no_role: {
        my $user = create_test_user();

        # In a "public" WS, a non-member user should have "read" Perm
        my $rc = $workspace->permissions->user_can(
            user       => $user,
            permission => ST_READ_PERM,
        );
        ok $rc, 'User has read Perm when not member in public WS';
    }
}
