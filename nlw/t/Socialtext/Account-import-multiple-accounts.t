#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 16;
use Test::Socialtext::Account qw/export_account import_account_ok/;
use Socialtext::CLI;
use File::Path qw(rmtree);

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# TEST: re-importing Accounts that have Users/Groups that cross-reference each
# other is possible *without* having to "--overwrite".
#
# Create two Accounts, with Users/Groups in each Account that reference the
# other Account.  We _should_ be able to export both Accounts, flush the
# system, and then re-import both of them back in.  Even though importing
# "Account A" auto-creates "Account B" in order to preserve User/Group Primary
# Account relationships, importing "Account B" *can* proceed without having to
# first nuke/flush the Account (which causes all of the links from B->A to be
# removed).
cross_account_reference_import_possible: {
    # Create two Accounts, some Workspaces, a Group, and some Users.
    my $pri_account   = create_test_account_bypassing_factory();
    my $pri_workspace = create_test_workspace(account => $pri_account);
    my $pri_group     = create_test_group(account => $pri_account);
    my $pri_user      = create_test_user(account => $pri_account);

    my $sec_account   = create_test_account_bypassing_factory();
    my $sec_workspace = create_test_workspace(account => $sec_account);
    my $sec_user      = create_test_user(account => $sec_account);

    # Set up some cross-referential relationships between the two Accounts.
    $pri_workspace->add_user(user => $sec_user);

    $sec_workspace->add_group(group => $pri_group);
    $pri_group->add_user(user => $pri_user);

    # Export both Accounts.
    my $pri_export = export_account($pri_account);
    my $sec_export = export_account($sec_account);

    # TEST: Import A, then B.
    import_primary_then_secondary: {
        Test::Socialtext->_remove_all_but_initial_objects();
        Socialtext::Cache->clear();

        # Import primary account; secondary should exist, but be a
        # "Placeholder".
        import_account_ok($pri_export);
        my $q_sec = Socialtext::Account->new(name => $sec_account->name);
        ok $q_sec->is_placeholder, '... a "placeholder"';

        # Import secondary account; it should no longer be a "Placeholder".
        import_account_ok($sec_export);
        $q_sec = Socialtext::Account->new(name => $sec_account->name);
        ok !$q_sec->is_placeholder, '... no longer a "placeholder"';
    }

    # TEST: Import B, then A.
    import_secondary_then_primary: {
        Test::Socialtext->_remove_all_but_initial_objects();
        Socialtext::Cache->clear();

        # Import secondary account; primary should exist, but be a
        # "Placeholder"
        import_account_ok($sec_export);
        my $q_pri = Socialtext::Account->new(name => $pri_account->name);
        ok $q_pri->is_placeholder, '... a "placeholder"';

        # Import primary account; it should no longer be a "Placeholder"
        import_account_ok($pri_export);
        $q_pri = Socialtext::Account->new(name => $pri_account->name);
        ok !$q_pri->is_placeholder, '... a "placeholder"';
    }

    # CLEANUP
    rmtree [$pri_export, $sec_export], 0;
}

