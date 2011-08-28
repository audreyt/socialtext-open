#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 70;
use Test::Socialtext::User;
use Test::Socialtext::Group;
use Test::Socialtext::Workspace;
use Test::Socialtext::Account;
use Test::Differences;
use Socialtext::CLI;
use Socialtext::Group::Factory;
use Test::Socialtext::CLIUtils qw(expect_success);
use File::Temp qw(tempdir);
use File::Path qw(rmtree);

fixtures("db");

###############################################################################
# CASE: Have "Default" Group, export w/Workspace, flush, Group is
# re-constituted on Workspace import, into its original Primary Account.
reconstitute_default_group_on_workspace_import: {
    clean_all_users();
    my $primary_account   = create_test_account_bypassing_factory();
    my $group             = create_test_group(account => $primary_account);
    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Export the Workspace
    export_and_import_workspace(
        workspace => $workspace,
        flush     => sub {
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Workspace->delete_recklessly($workspace);
            Test::Socialtext::Account->delete_recklessly($primary_account);
            Test::Socialtext::Account->delete_recklessly($secondary_account);
        },
    );

    # VERIFY: Group exists w/correctPrimary Account
    my $q_primary = Socialtext::Account->new(
        name => $primary_account->name,
    );
    my $q_group = Socialtext::Group->GetGroup(
        primary_account_id => $q_primary->account_id,
        driver_group_name  => $group->driver_group_name,
        created_by_user_id => $group->created_by_user_id,
    );
    isa_ok $q_group, 'Socialtext::Group',
        'Group reconstituted, w/correct Primary Account';
}

###############################################################################
# CASE: Have "Default" Group, export w/Workspace, Group membership list is
# merged on Workspace import.
merge_default_group_on_workspace_import: {
    clean_all_users();
    my $primary_account   = create_test_account_bypassing_factory();
    my $group             = create_test_group(account => $primary_account);
    my $user_one          = create_test_user(account => $primary_account);
    my $user_two          = create_test_user(account => $primary_account);
    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $group->add_user(user => $user_one);
    $workspace->add_group(group => $group);

    # Export the Workspace
    export_and_import_workspace(
        workspace => $workspace,
        flush => sub {
            # change Group membership, so we can verify that membership gets
            # merged in properly
            $group->remove_user(user => $user_one);
            $group->add_user(user => $user_two);

            # flush workspace
            Test::Socialtext::Workspace->delete_recklessly($workspace);
        },
    );

    # VERIFY: Group membership list was merged
    my @expected = map { $_->username } sort { $a->user_id <=> $b->user_id } ($user_one, $user_two);
    my @received = map { $_->username } sort { $a->user_id <=> $b->user_id } $group->users->all;
    eq_or_diff \@received, \@expected,
        'Group membership list merged on Workspace import';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Workspace, flush, Group is found again in
# LDAP, we just pull membership from LDAP (as we know any membership we import
# is going to get thrown away).
existing_ldap_group_on_workspace_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;
    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';

    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Export the Workspace
    export_and_import_workspace(
        workspace => $workspace,
        flush => sub {
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Workspace->delete_recklessly($workspace);
        },
    );

    # VERIFY: Peek into DB and make sure that the Group was re-vivified
    my %group_args = (
        primary_account_id => $group->primary_account->account_id,
        created_by_user_id => $group->created_by_user_id,
        driver_group_name  => $group->driver_group_name,
    );
    my $q_group_proto = Socialtext::Group->GetProtoGroup(%group_args);
    ok $q_group_proto, 'Group was re-vivified during import';

    # VERIFY: Group has Role in workspace
    my $q_group     = Socialtext::Group->GetGroup(%group_args);
    my $q_workspace = Socialtext::Workspace->new(
        name => $workspace->name,
    );
    ok $q_workspace->has_group($q_group), '... and was given Role in Workspace';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Workspace, flush, Group is not found in
# LDAP, but a matching "Default" Group is found in its original Primary
# Account (e.g. possible reconstituted Group from the past).  Membership is
# merged into the "Default" Group.
merge_to_default_an_ldap_group_on_workspace_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;

    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';
    is $group->user_count, 3, '... Users loaded too';

    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Export the Workspace
    my $new_group;
    export_and_import_workspace(
        workspace => $workspace,
        flush => sub {
            # flush the Group/Workspace
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Workspace->delete_recklessly($workspace);

            # create a new "Default" Group that the LDAP one will get merged
            # into
            $new_group = Socialtext::Group->Create( {
                primary_account_id => $primary_account->account_id,
                created_by_user_id => $group->created_by_user_id,
                driver_group_name  => $group->driver_group_name,
            } );
            $new_group->add_user(user => create_test_user());

            # turn off LDAP, so that we don't find the LDAP Group any more
            undef $openldap;
        },
    );
    ok $new_group, 'New "Default" Group created to be merged into';

    # VERIFY: Group membership list was merged in
    my $expected = 1 + $group->user_count;
    is $new_group->user_count, $expected, '... LDAP membership list merged in';

    # VERIFY: Group has Role in workspace
    my $q_workspace = Socialtext::Workspace->new(
        name => $workspace->name,
    );
    ok $q_workspace->has_group($new_group), '... and was given Role in Workspace';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Workspace, flush, Group is not found in
# LDAP, nor can a matching "Default" Group be found.  Group is re-constituted
# as a Default Group, in its original Primary Account.
reconstitute_as_default_group_an_ldap_group_on_workspace_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;
    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';
    is $group->user_count, 3, '... Users loaded too';

    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Export the Workspace
    export_and_import_workspace(
        workspace => $workspace,
        flush => sub {
            # flush the Group/Workspace
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Workspace->delete_recklessly($workspace);

            # turn off LDAP, so that we don't find the LDAP Group any more
            undef $openldap;
        },
    );

    # VERIFY: Group was reconstituted as a "Default" Group
    my $q_group = Socialtext::Group->GetGroup(
        primary_account_id => $group->primary_account_id,
        created_by_user_id => $group->created_by_user_id,
        driver_group_name  => $group->driver_group_name,
    );
    ok $q_group, 'Group was reconstituted';
    is $q_group->driver_name, 'Default', '... as a Default Group';

    # VERIFY: Group membership list was merged in
    is $q_group->user_count, $group->user_count, '... LDAP members loaded';

    # VERIFY: Group has Role in workspace
    my $q_workspace = Socialtext::Workspace->new(
        name => $workspace->name,
    );
    ok $q_workspace->has_group($q_group), '... and was given Role in Workspace';
}

###############################################################################
# CASE: Have "Default" Group, export w/Account, flush, Group is re-constituted
# on Account import, into original Primary Account.
reconsitute_default_group_on_account_import: {
    clean_all_users();
    my $primary_account   = create_test_account_bypassing_factory();
    my $group             = create_test_group(account => $primary_account);
    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $workspace->add_group(group => $group);

    # Export the Account
    export_and_import_account(
        account => $secondary_account,
        flush   => sub {
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Workspace->delete_recklessly($workspace);
            Test::Socialtext::Account->delete_recklessly($primary_account);
            Test::Socialtext::Account->delete_recklessly($secondary_account);
        },
    );

    # VERIFY: Group exists w/correctPrimary Account
    my $q_primary = Socialtext::Account->new(
        name => $primary_account->name,
    );
    my $q_group = Socialtext::Group->GetGroup(
        primary_account_id => $q_primary->account_id,
        driver_group_name  => $group->driver_group_name,
        created_by_user_id => $group->created_by_user_id,
    );
    isa_ok $q_group, 'Socialtext::Group',
        'Group reconstituted, w/correct Primary Account';
}

###############################################################################
# CASE: Have "Default" Group, export w/Account, Group membership list is
# merged on Account import.
reconsitute_default_group_on_account_import: {
    clean_all_users();
    my $primary_account   = create_test_account_bypassing_factory();
    my $group             = create_test_group(account => $primary_account);
    my $user_one          = create_test_user(account => $primary_account);
    my $user_two          = create_test_user(account => $primary_account);
    my $secondary_account = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $secondary_account);

    # Add the Group to the Workspace
    $group->add_user(user => $user_one);
    $workspace->add_group(group => $group);

    # Export the Account
    export_and_import_account(
        account => $secondary_account,
        flush   => sub {
            # change Group membership, so we can verify that membership gets
            # merged in properly
            $group->remove_user(user => $user_one);
            $group->add_user(user => $user_two);

            # flush account
            Test::Socialtext::Account->delete_recklessly($secondary_account);
        },
    );

    # VERIFY: Group membership list was merged
    my @expected = sort map { $_->username } ($user_one, $user_two);
    my @received = sort map { $_->username } $group->users->all;
    eq_or_diff \@received, \@expected,
        'Group membership list merged on Account import';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Account, flush, Group is found again in
# LDAP, we just pull membership from LDAP (as we know any membership we import
# is going to get thrown away).
existing_ldap_group_on_account_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;
    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';

    my $secondary_account = create_test_account_bypassing_factory();

    # Add the Group to the Account
    $secondary_account->add_group(group => $group);

    # Export the Account
    export_and_import_account(
        account => $secondary_account,
        flush   => sub {
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Account->delete_recklessly($primary_account);
            Test::Socialtext::Account->delete_recklessly($secondary_account);
        },
    );

    # VERIFY: Peek into DB and make sure that the Group was re-vivified
    my $q_primary = Socialtext::Account->new(
        name => $primary_account->name,
    );
    my %group_args = (
        primary_account_id => $q_primary->account_id,
        created_by_user_id => $group->created_by_user_id,
        driver_group_name  => $group->driver_group_name,
    );
    my $q_group_proto = Socialtext::Group->GetProtoGroup(%group_args);
    ok $q_group_proto, 'Group was re-vivified during import';

    # VERIFY: Group has Role in Account
    my $q_group     = Socialtext::Group->GetGroup(%group_args);
    my $q_secondary = Socialtext::Account->new(
        name => $secondary_account->name,
    );
    ok $q_secondary->has_group($q_group), '... and was given Role in Account';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Account, flush, Group is not found in LDAP
# but a matching "Default" Group is found in its original Primary Account
# (e.g. possibly reconstituted Group from the past).  Membership is merged
# into the "Default" Group.
merge_to_default_an_ldap_group_on_account_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;
    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

use Socialtext::SQL qw(sql_execute);
use Data::Dumper;
my $sth = sql_execute('select * from users');
warn Dumper $sth->fetchall_arrayref({});
    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';
    is $group->user_count, 3, '... Users loaded too';

    my $secondary_account = create_test_account_bypassing_factory();

    # Add the Group to the Account
    $secondary_account->add_group(group => $group);

    # Export the Account
    my $new_group;
    export_and_import_account(
        account => $secondary_account,
        flush   => sub {
            # flush
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Account->delete_recklessly($secondary_account);

            # create a "Default" Group that the LDAP one will get merged into
            $new_group = Socialtext::Group->Create( {
                primary_account_id => $group->primary_account_id,
                created_by_user_id => $group->created_by_user_id,
                driver_group_name  => $group->driver_group_name,
            } );
            $new_group->add_user(user => create_test_user());

            # turn off LDAP, so that we don't find the LDAP Group any more
            undef $openldap;
        },
    );
    ok $new_group, 'New "Default" Group created to be merged into';

    # VERIFY: Group membership list was merged in
    my $expected = 1 + $group->user_count;
    is $new_group->user_count, $expected, '... LDAP membership list merged in';

    # VERIFY: Group has Role in Account
    my $q_secondary = Socialtext::Account->new(
        name => $secondary_account->name,
    );
    ok $q_secondary->has_group($new_group), '... and was given Role in Account';
}

###############################################################################
# CASE: Have "LDAP" Group, export w/Account, flush, Group is not found in
# LDAP, nor can a matching "Default" Group be found.  Group is re-constituted
# as a Default Group, in its original Primary Account.
reconstitute_as_default_group_an_ldap_group_on_account_import: {
    clean_all_users();
    local $Socialtext::Group::Factory::Asynchronous = 0;
    my $openldap     = bootstrap_openldap();
    my $dn_motorhead = 'cn=Motorhead,dc=example,dc=com';

    my $primary_account = create_test_account_bypassing_factory();
    my $group           = Socialtext::Group->GetGroup(
        primary_account_id => $primary_account->account_id,
        driver_unique_id   => $dn_motorhead,
    );
    ok $group, 'Loaded Group from LDAP';
    is $group->user_count, 3, '... Users loaded too';

    my $secondary_account = create_test_account_bypassing_factory();

    # Add the Group to the Account
    $secondary_account->add_group(group => $group);

    # Export the Account
    export_and_import_account(
        account => $secondary_account,
        flush => sub {
            # flush the Group/Account
            Test::Socialtext::Group->delete_recklessly($group);
            Test::Socialtext::Account->delete_recklessly($secondary_account);

            # turn off LDAP, so that we don't find the LDAP Group any more
            undef $openldap;
        },
    );

    # VERIFY: Group was reconstituted as a "Default" Group
    my $q_group = Socialtext::Group->GetGroup(
        primary_account_id => $group->primary_account_id,
        created_by_user_id => $group->created_by_user_id,
        driver_group_name  => $group->driver_group_name,
    );
    ok $q_group, 'Group was reconstituted';
    is $q_group->driver_name, 'Default', '... as a Default Group';

    # VERIFY: Group membership list was merged in
    is $q_group->user_count, $group->user_count, '... LDAP members loaded';

    # VERIFY: Group has Role in Account
    my $q_secondary = Socialtext::Account->new(
        name => $secondary_account->name,
    );
    ok $q_secondary->has_group($q_group), '... and was given Role in Account';
}


###############################################################################
# Helper method to bootstrap OpenLDAP and feed it data.
sub bootstrap_openldap {
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
    ok $ldap->add_ldif('t/test-data/ldap/people.ldif'), 'added people';
    ok $ldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), 'added groups';
    return $ldap;
}

###############################################################################
# Helper method to export+reimport Account.
sub export_and_import_account {
    my %args    = @_;
    my $account = $args{account};
    my $flush   = $args{flush} || sub { };

    my $export_base = tempdir(CLEANUP => 1);
    my $export_dir  = File::Spec->catdir($export_base, 'account');

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [
                    '--account', $account->name,
                    '--dir',     $export_dir,
                ],
            )->export_account();
        },
        qr/account exported to/,
        'Account exported',
    );

    # Flush our test data.
    $flush->();
    Socialtext::Cache->clear();

    # Re-import the Account.
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--dir', $export_dir],
            )->import_account();
        },
        qr/account imported/,
        '... Account re-imported',
    );

    # CLEANUP
    rmtree [$export_base], 0;
}

###############################################################################
# Helper method to export+reimport Workspace.
sub export_and_import_workspace {
    my %args = @_;
    my $workspace = $args{workspace};
    my $flush   = $args{flush} || sub { };

    my $export_dir = tempdir(CLEANUP => 1);
    my $tarball = $workspace->export_to_tarball(dir => $export_dir);

    # Flush our test data.
    $flush->();
    Socialtext::Cache->clear();

    # Re-import the Workspace.
    Socialtext::Workspace->ImportFromTarball(tarball => $tarball);

    # CLEANUP
    rmtree [$export_dir], 0;
}

sub clean_all_users {
    for my $user (Socialtext::User->All->all()) {
        next if $user->is_system_created;
        Test::Socialtext::User->delete_recklessly($user);
    }
}
