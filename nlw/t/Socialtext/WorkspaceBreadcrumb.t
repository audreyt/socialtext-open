#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use DateTime;
use Test::Socialtext tests => 7;

BEGIN {
    use_ok "Socialtext::WorkspaceBreadcrumb";
}

fixtures(qw( db ));

###############################################################################
# TEST: save breadcrumb
save_breadcrumb: {
    my $hub   = create_test_hub();
    my $crumb = Socialtext::WorkspaceBreadcrumb->Save(
        workspace_id => $hub->current_workspace->workspace_id,
        user_id      => $hub->current_user->user_id,
    );
    isa_ok $crumb, 'Socialtext::WorkspaceBreadcrumb', 'Saved breadcrumb';
    ok $crumb->timestamp, '... timestamp was set during save';
}

###############################################################################
# TEST: updating an existing breadcrumb
updating_breadcrumb: {
    my $hub   = create_test_hub();
    my $crumb = Socialtext::WorkspaceBreadcrumb->Save(
        workspace_id => $hub->current_workspace->workspace_id,
        user_id      => $hub->current_user->user_id,
    );
    my $updated = Socialtext::WorkspaceBreadcrumb->Save(
        workspace_id => $hub->current_workspace->workspace_id,
        user_id      => $hub->current_user->user_id,
    );

    my $cmp = DateTime->compare(
        $crumb->parsed_timestamp,
        $updated->parsed_timestamp,
    );
    is $cmp, -1, 'Timestamp updated in breadcrumb';
}

###############################################################################
# TEST: breadcrumbs returned in proper order
list_multiple_breadcrumbs_in_order: {
    my $hub        = create_test_hub();
    my @workspaces = (
        $hub->current_workspace,
        create_test_workspace(user => $hub->current_user),
        create_test_workspace(user => $hub->current_user),
        create_test_workspace(user => $hub->current_user),
    );

    # Save a bunch of breadcrumbs
    foreach my $ws (@workspaces) {
        Socialtext::WorkspaceBreadcrumb->Save(
            workspace_id => $ws->workspace_id,
            user_id      => $hub->current_user->user_id,
        );
    }

    # Crumbs should be returned in *reverse* order
    my @got =
        map { $_->name }
        Socialtext::WorkspaceBreadcrumb->List(
            user_id => $hub->current_user->user_id,
            limit   => 10,
        );

    my @ws_names = map { $_->name } @workspaces;
    my @expected = reverse @ws_names;
    is_deeply \@got, \@expected,
        'Crumbs returned in correct order (newest->oldest)';
}

###############################################################################
# TEST: breadcrumbs with limit
list_multiple_breadcrumbs_with_limit: {
    my $hub        = create_test_hub();
    my @workspaces = (
        $hub->current_workspace,
        create_test_workspace(user => $hub->current_user),
        create_test_workspace(user => $hub->current_user),
        create_test_workspace(user => $hub->current_user),
    );

    # Save a bunch of breadcrumbs
    foreach my $ws (@workspaces) {
        Socialtext::WorkspaceBreadcrumb->Save(
            workspace_id => $ws->workspace_id,
            user_id      => $hub->current_user->user_id,
        );
    }

    # Crumbs should be returned in correct order, and with the proper limit.
    # - the two most recent crumbs should be returned, in newest->oldest order
    my @got =
        map { $_->name }
        Socialtext::WorkspaceBreadcrumb->List(
            user_id => $hub->current_user->user_id,
            limit   => 2,
        );
    my @ws_names = map { $_->name } @workspaces;
    my @expected = reverse @ws_names;
    splice @expected, 2;                # only keep first two elems
    is_deeply \@got, \@expected,
        'Crumbs limited and returned in correct order';
}

###############################################################################
# TEST: breadcrumbs for User that hasn't set any
list_breadcrumbs_empty_user: {
    my $hub        = create_test_hub();
    my $empty_user = create_test_user();

    # make the User a member of the WS, so we _know_ its got nothing to do
    # with perms; its just "did he save a breadcrumb here or not".
    $hub->current_workspace->add_user( user => $empty_user );

    # create a breadcrumb for some _other_ User in the WS
    Socialtext::WorkspaceBreadcrumb->Save(
        workspace_id => $hub->current_workspace->workspace_id,
        user_id      => $hub->current_user->user_id,
    );

    # our Empty User should have _no_ breadcrumbs in this WS
    my @crumbs = Socialtext::WorkspaceBreadcrumb->List(
        user_id => $empty_user->user_id,
        limit   => 10,
    );
    ok !@crumbs, 'Empty User has _no_ breadcrumbs';
}
