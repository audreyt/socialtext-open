#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 15;
use File::Spec;
use YAML qw(LoadFile);
use Socialtext::AppConfig;
use Socialtext::Workspace;
use ok 'Socialtext::Workspace::Exporter';

fixtures(qw( db ));

###############################################################################
# TEST: AUW export only includes *direct* memberships
auw_export_only_contains_direct_memberships: {
    my $tmpdir = Socialtext::AppConfig->test_dir();

    # Create an AUW
    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace(account => $acct);
    $ws->add_account(account => $acct);
    ok 1, 'Created an AUW';

    # Create some Users/Groups with direct membership in the WS
    my $direct_user  = create_test_user(account => $acct);
    my $direct_group = create_test_group(account => $acct);

    $ws->add_user(user => $direct_user);
    $ws->add_group(group => $direct_group);

    # Create some Users/Groups with *INDIRECT* membership in the WS, by virtue
    # of it being an AUW and these things living in the same Acct as the WS.
    my $indirect_user  = create_test_user(account  => $acct);
    my $indirect_group = create_test_group(account => $acct);

    # Make sure that all of the Users/Groups have access to the WS (they
    # should; its an AUW).
    ok $ws->has_user($direct_user),     '... this User has access';
    ok $ws->has_group($direct_group),   '... this Group has access';
    ok $ws->has_user($indirect_user),   '... this User has access, indirectly';
    ok $ws->has_group($indirect_group), '... this Group has access, indirectly';

    my $wx = Socialtext::Workspace::Exporter->new(
        name => $ws->name, workspace => $ws
    );

    # Export the Workspace info, and check for *DIRECT* Groups only
    direct_groups_only: {
        $wx->export_info();
        my $file = $wx->filename($ws->name.'-info.yaml');

        ok -e $file, '... exported WS info to YAML file';
        my $yaml   = LoadFile($file);
        my @groups = @{$yaml->{groups}};
        is @groups, 1, '... ... containing a single Group';
        is $groups[0]{driver_group_name}, $direct_group->driver_group_name,
            '... ... one w/Direct access';
    }

    # Export the Workspace membership list for Users, and check that the Users
    # with indirect membership in WS got flagged properly with "indirect: 1"
    direct_users_or_marked: {
        $wx->export_users();
        my $file = $wx->filename($ws->name.'-users.yaml');

        ok -e $file, '... exported WS Users to YAML file';
        my $yaml  = LoadFile($file);
        is @{$yaml}, 2, '... ... containing two Users';

        my $user = shift @{$yaml};
        ok !exists $user->{indirect}, '... ... one Direct';
        is $user->{username}, $direct_user->username,
            '... ... ... our Direct User';

        $user = shift @{$yaml};
        is $user->{indirect}, 1, '... ... one Indirect';
        is $user->{username}, $indirect_user->username,
            '... ... ... our Indirect User';
    }
}
