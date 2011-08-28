#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML qw(LoadFile);
use File::Temp qw(tempdir);
use File::Path qw(rmtree);
use Test::Socialtext tests => 32;
use Test::Deep;

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# Helper function; dump a User to a hash, like ST::Account does
sub dump_user {
    my $user = shift;
    return unless $user;

    my $data = $user->to_hash;
    delete $data->{primary_account_id};
    delete $data->{user_id};
    $data->{profile} = ignore();            # ignore PPL Profile in dumps
    $data->{restrictions} = ignore();       # ignore User Restrictions in dumps

    for my $acct ($user->accounts) {
        $data->{roles}{ $acct->name } = $acct->role_for_user($user)->name;
    }
    return $data;
}

###############################################################################
# Helper function; dump a Group to a hash, like ST::P::Plugin::Groups does
sub dump_group {
    my $group = shift;
    return unless $group;

    my $data = {
        group_id             => $group->group_id,
        primary_account_name => $group->primary_account->name,
        driver_group_name    => $group->driver_group_name,
        creation_datetime    => ignore(),
        created_by_username  => $group->creator->username,
        permission_set       => $group->permission_set,
        photo                => ignore(),
        role_name            => ignore(),
        users                => ignore(),
        description          => ignore(),
        containers           => ignore(),
    };
    return $data;
}

sub dump_signal {
    my $signal = shift;
    return unless $signal;

    my $data = {
        body => $signal->body,
        at => ignore(),
        hidden => $signal->is_hidden,
        signal_id => ignore(),
        username => $signal->user->username,
        group_ids => $signal->group_ids,
        account_ids => $signal->account_ids,
        attachments => $signal->attachments,
        page_ids => undef,
        workspace_names => undef,
    };
    return $data;
}

###############################################################################
# Helper function; export Account, check if the User/Group is in the exported
# data.
sub account_export_contains { # MARK
    my %args    = @_;
    my $account = $args{account};
    my $groups  = $args{groups} || [];
    my $users   = $args{users}  || [];
    my $signals = $args{signals}|| [];
    my $prefix  = $args{prefix};

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    # Export the Account
    my $adapter  = Socialtext::Pluggable::Adapter->new();
    my $hub      = $adapter->make_hub( Socialtext::User->SystemUser );
    my $tempdir  = tempdir();
    my $filename = $account->export(dir => $tempdir, hub => $hub);
    ok -f $filename, "$prefix - exported ok";

    # Check the exported data set to verify that the Users/Groups we're
    # expecting are actually in it.
    my @expected_users  = map { dump_user($_) } @{$users};
    my @expected_groups = map { dump_group($_) } @{$groups};
    my @expected_signals = map { dump_signal($_) } @{$signals};

    my $results = LoadFile($filename);
    $results->{groups} ||= [];

    cmp_deeply $results->{users},  \@expected_users,  "$prefix - User list";
    cmp_deeply $results->{groups}, \@expected_groups, "$prefix - Group list";
    cmp_deeply $results->{signals}, \@expected_signals, "$prefix - Signal list"
        if @expected_signals;

    # CLEANUP
    rmtree [$tempdir], 0;
}

###############################################################################
# TEST: Account export includes Users who have the Account as their Primary
# Account
includes_users_with_primary_account : {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    account_export_contains(
        prefix  => 'Includes User w/Account as his Primary Account',
        account => $account,
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export includes Users who have a direct Role in the Account
includes_users_with_direct_role : {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    $account->add_user(user => $user);

    account_export_contains(
        prefix  => 'Includes User w/direct Role in the Account',
        account => $account,
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export includes Users who have an indirect Role via a Group
# which has this Account as its Primary Account (e.g. User->Group->Account)
includes_users_in_group_with_primary_account : {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group(account => $account);
    my $user    = create_test_user();

    $group->add_user(user => $user);

    account_export_contains(
        prefix  => 'Includes User w/Role via Group w/Primary Account',
        account => $account,
        groups  => [$group],
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export includes Users who have an indirect Role via a Group
# which has a Role in the Account (e.g. User->Group->Account)
includes_users_in_group_with_direct_role : {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();
    my $user    = create_test_user();

    $account->add_group(group => $group);
    $group->add_user(user => $user);

    account_export_contains(
        prefix  => 'Includes User w/Role via Group w/Role in Account',
        account => $account,
        groups  => [$group],
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export includes Users who have an indirect Role via Workspace
# membership (e.g. User->Workspace->Account).
#
# These Users are *also* exported as part of the Workspace exports, but are
# exported along with the Account so that we can ensure that we've got all of
# the Users that have a Role in the Account.
includes_users_with_only_indirect_workspace_role : {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $user      = create_test_user();

    $workspace->add_user(user => $user);

    account_export_contains(
        prefix  => 'Includes User w/Role via Workspace',
        account => $account,
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export includes Users who have an indirect Role via
# Group+Workspace membership (e.g. User->Group->Workspace->Account).
#
# These Users are *also* exported as part of the Workspace exports, but are
# exported along with the Account so that we can ensure that we've got all of
# the Users that have a Role in the Account.
includes_users_with_only_indirect_group_workspace_role : {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user      = create_test_user();

    $workspace->add_group(group => $group);
    $group->add_user(user => $user);

    ok $workspace->has_group($group), 'workspace has group';
    ok $workspace->has_user($user), 'workspace has user';
    ok $account->has_group($group), 'account has group';
    ok $account->has_user($user), 'account has user';

    account_export_contains(
        prefix  => 'Includes User w/Role via Group w/Role in Workspace',
        account => $account,
        groups  => [$group],
        users   => [$user],
    );
}

###############################################################################
# TEST: Account export is possible when a User has a hidden People Profile.
#
# Test covers Bug #3261, where we'd attempt to call "$profile->to_hash()"
# without actually having a Profile object to serialize.
export_succeeds_when_profile_hidden: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    $user->update_store(
        is_profile_hidden   => 1,
    );

    account_export_contains(
        prefix  => 'Includes User with hidden ST People Profile',
        account => $account,
        users   => [$user],
    );
}

###############################################################################
# Test that signals to a group in this account is included.
Export_signals_to_group: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);
    my $group   = create_test_group();
    $group->add_user(user => $user);
    $account->add_group(group => $group);

    my $sig = Socialtext::Signal->Create(
        body      => 'o hai',
        group_ids => [ $group->group_id ],
        user_id   => $user->user_id,
    );
    $sig->clear_user; # remove the ref to $user, so we re-create it later.

    account_export_contains(
        prefix  => 'Includes User with hidden ST People Profile',
        account => $account,
        users   => [$user],
        groups  => [$group],
        signals => [$sig],
    );
}

###############################################################################
# TEST: Account export includes a User's "middle_name".
includes_users_middle_name: {
    my $middle_name = 'Ulysses';
    my $account     = create_test_account_bypassing_factory();
    my $user        = create_test_user(
        account     => $account,
        middle_name => $middle_name,
    );

    account_export_contains(
        prefix  => "Includes User' middle name",
        account => $account,
        users   => [$user],
    );
}
