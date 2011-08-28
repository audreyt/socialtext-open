#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 16;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it.
fixtures(qw( db ));

use_ok 'Socialtext::Group';

group_with_no_workspaces: {
    my $group      = create_test_group();
    my $workspaces = $group->workspaces();

    isa_ok $workspaces, 'Socialtext::MultiCursor', 'got a list of workspaces';
    is $workspaces->count(), 0, '... with the correct count';
    is $group->workspace_count, 0, "... same count, different accessor";
}

group_has_workspaces: {
    my $user   = create_test_user();
    my $ws_one = create_test_workspace(user => $user);
    my $ws_two = create_test_workspace(user => $user);
    my $group  = create_test_group();

    # Create GWRs, giving the Group a default Role
    $ws_one->add_group(group => $group);
    $ws_two->add_group(group => $group);

    is $group->workspace_count, 2, "two workspaces";
    my $workspaces = $group->workspaces();

    isa_ok $workspaces, 'Socialtext::MultiCursor', 'got a list of workspaces';
    is $workspaces->count(), 2, '... with the correct count';
    isa_ok $workspaces->next(), 'Socialtext::Workspace', '... queried Workspace';
}

group_has_distinct_workspaces: {
    my $user   = create_test_user();
    my $ws_one = create_test_workspace(user => $user);
    my $ws_two = create_test_workspace(user => $user);
    my $group1 = create_test_group();
    my $group2 = create_test_group();

    $ws_one->add_group(group => $group1);

    # set up two paths to the second workspace from group 1
    $ws_two->add_group(group => $group1);
    $ws_two->add_group(group => $group2);
    $group2->add_group(group => $group1);

    is $group1->workspace_count, 2, "two workspaces for group 1";
    is $group2->workspace_count, 1, "just one workspace for group 2";

    my $workspaces = $group1->workspaces();
    isa_ok $workspaces, 'Socialtext::MultiCursor', 'got a list of workspaces';
    is $workspaces->count(), 2, '... with the correct count';
    isa_ok $workspaces->next(), 'Socialtext::Workspace', '... queried Workspace';
}

group_exclude_auw_paths: {
    my $user   = create_test_user();
    my $acct = create_test_account_bypassing_factory();
    my $ws_one = create_test_workspace(account => $acct, user => $user);
    $ws_one->add_account(account => $acct);
    my $group = create_test_group(account => $acct);

    my $workspaces = $group->workspaces();
    is $workspaces->count, 1, 'auw is counted';

    $workspaces = $group->workspaces(exclude_auw_paths => 1);
    is $workspaces->count, 0, 'auw is NOT counted';

    $ws_one->add_group(group => $group, role => 'admin');

    $workspaces = $group->workspaces(exclude_auw_paths => 1);
    is $workspaces->count, 1, 'workspace is deliberate';
}
