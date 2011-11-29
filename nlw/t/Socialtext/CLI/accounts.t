#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Cwd;
use File::Path qw(rmtree);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use Test::Socialtext;
use Socialtext::CLI;
use Socialtext::SQL qw(:exec);
use Test::Socialtext::CLIUtils qw(expect_success expect_failure);

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# TEST: List Accounts, by name
list_accounts_by_name: {
    my $sql      = q{SELECT name FROM "Account" ORDER BY name};
    my $sth      = sql_execute($sql);
    my @accounts = map { $_->[0] } @{ $sth->fetchall_arrayref };

    expect_success(
        sub {
            Socialtext::CLI->new()->list_accounts();
        },
        (join '', map { "$_\n" } @accounts),
        'list-accounts by name',
    );
}

###############################################################################
# TEST: List Accounts, by id (although its still ordered by name)
list_accounts_by_id: {
    my $sql      = q{SELECT account_id FROM "Account" ORDER BY name};
    my $sth      = sql_execute($sql);
    my @accounts = map { $_->[0] } @{ $sth->fetchall_arrayref };

    expect_success(
        sub {
            Socialtext::CLI->new( argv => ['--ids'] )->list_accounts();
        },
        (join '', map { "$_\n" } @accounts),
        'list-accounts by id',
    );

}

###############################################################################
# TEST: Show Account config
show_account_config: {
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [
                    qw/ --account Socialtext /
                ]
            )->show_account_config();
        },
        qr/modules_installed/,
        'show-account-config success',
    );
}

###############################################################################
# TEST: Set Account Config with a prefs index.
config_with_prefs_index: {
    my $acct = create_test_account_bypassing_factory();
    my $name = $acct->name;

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct->name, '--index', 'theme',
                          'primary_color', '#cc6600' ],
            )->set_account_config();
        },
        qr/\QUpdated the theme prefs for the $name account\E/,
        'set account config successful when using a valid index',
    );

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct->name, '--index', 'theme',
                          'background_image_id', '-null-' ],
            )->set_account_config();
        },
        qr/\QUpdated the theme prefs for the $name account\E/,
        'set account config successful when using -null- for image id',
    );

    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct->name, '--index', 'theme',
                          'primary_color', 'ENOSUCH' ],
            )->set_account_config();
        },
        qr/One or more values for the theme index are invalid/,
        'set account config failure when using bad values for theme index',
    );
}

###############################################################################
# TEST: Exporting a non-existent Account
export_non_existent_account: {
    my $bogus_account = 'no-existy';
    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => ['--account', $bogus_account],
            )->export_account();
        },
        qr/There is no account named "$bogus_account"/,
        'Exporting invalid account fails',
    );
}

###############################################################################
# TEST: Export an Account
export_account: {
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name();

    # custom export root
    my $export_root = Cwd::abs_path(tempdir());
    local $ENV{ST_EXPORT_DIR} = $export_root;

    # export the Account
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--account', $acct_name],
            )->export_account();
        },
        qr/$acct_name account exported to/,
        'Exported valid account',
    );

    # export directory should exist, and contain "accounts.yaml" file.
    my $export_dir = File::Spec->catdir(
        $export_root,
        "${acct_name}.id-" . $account->account_id . ".export"
    );
    ok -e $export_dir, '... export directory exists';
    ok -f "$export_dir/account.yaml", '... account.yaml file exists';

    # CLEANUP
    rmtree [$export_root], 0;
}

###############################################################################
# TEST: Import an Account
import_account: {
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name();

    # custom export root
    my $export_root = Cwd::abs_path(tempdir());
    local $ENV{ST_EXPORT_DIR} = $export_root;

    # export the Account
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--account', $acct_name],
            )->export_account();
        },
        qr/$acct_name account exported to/,
        'Exported valid account',
    );

    # Calculate where the Account got exported to
    my $export_dir = File::Spec->catdir(
        $export_root,
        "${acct_name}.id-" . $account->account_id . ".export"
    );

    # re-import the Account, under a new name
    my $new_name = 'Fred';
    my $imported = Socialtext::Account->new(name => $new_name);
    ok !$imported, "... target Account doesn't exist yet";

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--dir', $export_dir, '--name', $new_name],
            )->import_account();
        },
        qr/$new_name account imported/,
        '... Account imported',
    );

    $imported = Socialtext::Account->new(name => $new_name);
    ok $imported, '... import was successful';
}

###############################################################################
# TEST: Importing Account w/Groups recreates the Group's Primary Account if it
# doesn't exist yet.
import_account_recreates_group_primary_account: {
    my $primary_acct = create_test_account_bypassing_factory();
    my $primary_name = $primary_acct->name();

    my $secondary_acct = create_test_account_bypassing_factory();
    my $secondary_name = $secondary_acct->name();

    my $group = create_test_group(account => $primary_acct);
    $secondary_acct->add_group(group => $group);

    my $export_dir = tempdir();

    # Export the Secondary Account
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--account', $secondary_name, '--dir', $export_dir, '--force'],
            )->export_account();
        },
        qr/$secondary_name account exported to/,
        'Exported Secondary Account',
    );

    # PURGE both the Primary+Secondary Accounts
    Test::Socialtext::Account->delete_recklessly($primary_acct);
    my $requery_primary = Socialtext::Account->new(name => $primary_name);
    ok !defined $requery_primary, '... Primary Account has been purged';

    Test::Socialtext::Account->delete_recklessly($secondary_acct);
    my $requery_secondary = Socialtext::Account->new(name => $secondary_name);
    ok !defined $requery_secondary, '... Secondary Account has been purged';

    # Import the Secondary Account
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--dir', $export_dir],
            )->import_account();
        },
        qr/$secondary_name account imported/,
        '... Secondary Account re-imported',
    );

    # VERIFY: the Primary Account should have been re-created
    $requery_primary   = Socialtext::Account->new(name => $primary_name);
    $requery_secondary = Socialtext::Account->new(name => $secondary_name);
    ok defined $requery_primary,   '... Primary Account re-created';
    ok defined $requery_secondary, '... Secondary Account re-created';

    # CLEANUP
    rmtree [$export_dir], 0;
}

done_testing;
