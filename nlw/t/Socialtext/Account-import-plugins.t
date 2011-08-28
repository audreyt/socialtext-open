#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 9;
use Socialtext::CLI;
use Test::Socialtext::Account;
use Test::Output qw(combined_from);
use Test::Socialtext::CLIUtils qw(expect_success);
use Socialtext::Account;
use Socialtext::Pluggable::Adapter;
use Socialtext::Pluggable::Plugin::Signals;
use File::Temp qw(tempdir);
use File::Path qw(rmtree);
use YAML qw(LoadFile DumpFile);

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# TEST: Importing an Account onto a machine that's missing one of the Plugins
# that was enabled in the Account on export shouldn't be fatal; just skip the
# missing Plugin.
missing_plugin: {
    my $account = create_test_account_bypassing_factory();
    my $name    = $account->name;
    my $plugin  = 'nonexistent';
    my $results = export_and_import_results(
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
        mangle  => sub {
            my $acct_data = shift;
            push @{$acct_data->{plugins}}, $plugin;
        }
    );
    like $results, qr/account imported/, '... import successful';
    like $results, qr/'$plugin' plugin missing; skipping/,
        '... skipping the missing plugin';

    # Re-instantiate the account with restored values
    $account = Socialtext::Account->Resolve($name);
    my $settings = Socialtext::Pluggable::Adapter->new()->account_preferences(
        account => $account,
        with_defaults => 0,
    );
    is_deeply $settings, {}, 'restored account uses default plugin prefs';
}

plugin_prefs: {
    my $account = create_test_account_bypassing_factory();
    my $name    = $account->name;

    # Set up some plugin prefs.
    $account->enable_plugin('signals');
    my $prefs   = Socialtext::Pluggable::Plugin::Signals->GetAccountPluginPrefTable($account->account_id);
    $prefs->set(signals_size_limit => 200);

    my $results = export_and_import_results(
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
    );
    like $results, qr/account imported/, '... import successful';

    # Re-instantiate the account with restored values
    $account = Socialtext::Account->Resolve($name);
    my $settings = Socialtext::Pluggable::Adapter->new()->account_preferences(
        account => $account,
        with_defaults => 0,
    );
    is_deeply $settings, {signals => {signals_size_limit => 200}},
        'restored account uses custom plugin prefs';
}

###############################################################################
# Helper routine to export an Account, and return the CLI output generated
# during the import.  Supports optional mangling of the exported YAML data.
sub export_and_import_results {
    my %args    = @_;
    my $account = $args{account};
    my $flush   = $args{flush}  || sub { };
    my $mangle  = $args{mangle} || sub { };

    my $export_base  = tempdir(CLEANUP => 1);
    my $export_dir   = File::Spec->catdir($export_base, 'account');
    my $account_yaml = File::Spec->catfile($export_dir, 'account.yaml');

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

    # Mangle the exported Account's YAML file
    my $data = LoadFile($account_yaml);
    $mangle->($data);
    DumpFile($account_yaml, $data);

    # Re-import the Account.
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => ['--dir', $export_dir],
            )->import_account();
        };
    } );

    # CLEANUP
    rmtree [$export_base], 0;

    # Return the results
    return $output;
}
