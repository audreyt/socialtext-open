#!/usr/bin/env perl

use strict;
use warnings;
use YAML qw();
use File::Temp qw(tempdir);
use Test::Socialtext tests => 12;
use Test::Socialtext::Account qw(export_account import_account_ok);
use Test::Socialtext::Workspace;
use Test::Socialtext::Group;
use Test::Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: "users.private_external_id" is preserved across Account export/import
private_external_id_is_preserved: {
    # Create an Account, WS, Group, and some Users to test with.
    my $account    = create_test_account_bypassing_factory();
    my $workspace  = create_test_workspace(account => $account);
    my $group      = create_test_group(account => $account);

    # ... User with only access to the Account
    my $no_ws_id   = Test::Socialtext->create_unique_id();
    my $user_no_ws = create_test_user(
        account             => $account,
        private_external_id => $no_ws_id,
    );

    # ... User with a Workspace membership in the Account
    my $in_ws_id   = Test::Socialtext->create_unique_id();
    my $user_in_ws = create_test_user(
        account             => $account,
        private_external_id => $in_ws_id,
    );
    $workspace->add_user(user => $user_in_ws);

    # ... User who only has access to the Account through a Group
    my $in_group_id   = Test::Socialtext->create_unique_id();
    my $user_in_group = create_test_user(
        private_external_id => $in_group_id,
    );
    $group->add_user(user => $user_in_group);

    # Export the Account, and make sure that the "private_external_id" was
    # exported for all of the Users.
    my $export_dir = export_account($account);
    {
        my $export_file = "$export_dir/account.yaml";
        my $results     = YAML::LoadFile($export_file);
        my @users       = @{ $results->{users} };
        is @users, 3, '... with correct number of Users';

        my @with_ids = grep { defined $_->{private_external_id} } @users;
        is @with_ids, 3, '... all of which have a private/external id';
    }

    # FLUSH THE SYSTEM, so the import starts from a clean slate.
    {
        Test::Socialtext::User->delete_recklessly($user_no_ws);
        Test::Socialtext::User->delete_recklessly($user_in_ws);
        Test::Socialtext::User->delete_recklessly($user_in_group);
        Test::Socialtext::Group->delete_recklessly($group);
        Test::Socialtext::Workspace->delete_recklessly($workspace);
        Test::Socialtext::Account->delete_recklessly($account);
        Socialtext::Cache->clear();

        my $user;
        $user = Socialtext::User->new(username => $user_no_ws->username);
        ok !$user, '... User with no WS membership was purged';

        $user = Socialtext::User->new(username => $user_in_ws->username);
        ok !$user, '... User with WS membership was purged';

        $user = Socialtext::User->new(username => $user_in_group->username);
        ok !$user, '... User with group membership was purged';
    }

    # Re-import the Account, and make sure that the Users still have their
    # "private_external_id"s
    import_account_ok($export_dir);
    {
        my $user;

        $user = Socialtext::User->new(username => $user_no_ws->username);
        is $user->private_external_id, $no_ws_id,
            '... User with no WS membership has external id preserved';

        $user = Socialtext::User->new(username => $user_in_ws->username);
        is $user->private_external_id, $in_ws_id,
            '... User with WS membership has external id preserved';

        $user = Socialtext::User->new(username => $user_in_group->username);
        is $user->private_external_id, $in_group_id,
            '... User with Group membership has external id preserved';
    }
}
