#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 3;

fixtures(qw( db ));

###############################################################################
# TEST: Export/Import Self-Join Workspace
import_self_join_workspace: {
    my $acct = create_test_account_bypassing_factory();

    # Create a Self-Join WS
    my $ws      = create_test_workspace(account => $acct);
    my $ws_name = $ws->name;
    $ws->permissions->set(set_name => 'self-join');
    is $ws->permissions->current_set_name, 'self-join', 'Have a self-join WS';

    # Create a Self-Join Group
    my $group    = create_test_group();
    my $group_id = $group->driver_unique_id;
    $group->update_store( { permission_set => 'self-join' } );
    is $group->permission_set, 'self-join', '... and a self-join Group';

    # Add the Group to the WS
    $ws->add_group(group => $group);

    # Export the WS, then nuke it.
    my $test_dir = Socialtext::AppConfig->test_dir();
    my $tarball  = $ws->export_to_tarball(dir => $test_dir);
    $ws->delete();

    # Re-import the Workspace
    Socialtext::Workspace->ImportFromTarball(tarball => $tarball);

    # Refresh the Workspace and make sure the Group got added properly.
    $ws = Socialtext::Workspace->new(name => $ws_name);
    ok $ws->has_group($group), '... and Group was added back to WS';
}
