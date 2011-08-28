#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 37;
use Socialtext::Account;
use Sys::Hostname;
use Cwd;

BEGIN { use_ok 'Socialtext::CLI' }
use Test::Socialtext::CLIUtils qw/expect_failure expect_success call_cli_argv/;

fixtures('db');

my $acct = create_test_account_bypassing_factory();
my $acct_name = $acct->name;

account_plugins: {
    expect_failure(
        call_cli_argv(enable_plugin => 
            '--account' => $acct_name,
            qw(--plugin foo)
        ),
        qr/Plugin foo does not exist!/,
        'enable invalid plugin',
    );
    expect_failure(
        call_cli_argv(enable_plugin =>
            qw(--account no-existy --plugin test)
        ),
        qr/There is no account named "no-existy"/,
        'enable plugin for invalid account',
    );
    expect_success(
        call_cli_argv(enable_plugin => 
            '--account' => $acct_name,
            qw(--plugin test)
        ),
        qr/The test plugin is now enabled for account \Q$acct_name/,
        'enable plugin for account',
    );
    expect_success(
        call_cli_argv(disable_plugin => 
            '--account' => $acct_name,
            qw(--plugin test)
        ),
        qr/The test plugin is now disabled for account \Q$acct_name/,
        'disabled plugin for account',
    );

    expect_success(
        call_cli_argv(enable_plugin => 
            qw(--all-accounts --plugin test)
        ),
        qr/The test plugin is now enabled for all accounts/,
        'enable plugin for all account',
    );
    expect_success(
        call_cli_argv(disable_plugin => 
            qw(--all-accounts --plugin test)
        ),
        qr/The test plugin is now disabled for all accounts/,
        'disable plugin for all account',
    );

    expect_failure(
        call_cli_argv(enable_plugin => 
            qw(--plugin test)
        ),
        qr/requires an account/,
        'enable plugin for all account without --all-accounts',
    );

    expect_success(
        call_cli_argv(enable_plugin => 
            qw(--all-accounts --plugin dashboard)
        ),
        qr/The dashboard plugin is now enabled for all accounts/,
        'enable plugin for all account',
    );
    expect_success(
        call_cli_argv(disable_plugin => 
            qw(--all-accounts --plugin dashboard)
        ),
        qr/The dashboard plugin is now disabled for all accounts/,
        'disable plugin for all account',
    );

    # Multi-plugin functionality is also exercised in plugin-pref.t
    expect_failure(
        call_cli_argv(enable_plugin => qw(--all-accounts --plugin socialcalc)),
        qr/The socialcalc plugin can not be set at the account scope/,
        'out of scope account plugin fails'
    );

    expect_success(
        call_cli_argv(enable_plugin => qw(--all-accounts --plugin all)),
        qr/The [-a-z]+ plugin is now enabled for all accounts/,
        'enable all plugins on all accounts works'
    );
}

my $ws = create_test_workspace(account => $acct);
my $ws_name = $ws->name;

workspace_plugins: {
    expect_failure(
        call_cli_argv(enable_plugin => 
            qw(--plugin test --workspace)
        ),
        qr/requires an account or a workspace/,
        'missing workspace name',
    );

    expect_success(
        call_cli_argv(enable_plugin => 
            qw(--plugin socialcalc), '--workspace' => $ws_name
        ),
        qr/The socialcalc plugin is now enabled for workspace \Q$ws_name/,
        'enable valid plugin for workspace',
    );

    # only certain plugins can be enabled on a per-workspace basis.
    expect_failure(
        call_cli_argv(enable_plugin => 
            qw(--plugin test), '--workspace' => $ws_name
        ),
        qr/The test plugin can not be set at the workspace scope/,
        'enable account-scope-only plugin for workspace',
    );
    expect_failure(
        call_cli_argv(disable_plugin => 
            qw(--plugin test), '--workspace' => $ws_name
        ),
        qr/The test plugin can not be set at the workspace scope/,
        'disable account-scope-only plugin',
    );

    # Disable workspace plugins.
    expect_success(
        call_cli_argv(disable_plugin => 
            qw(--plugin socialcalc), '--workspace' => $ws_name
        ),
        qr/The socialcalc plugin is now disabled for workspace \Q$ws_name/,
        'disable valid plugin',
    );

    # show workspace config lists plugins enabled for that workspace
    expect_success(
        call_cli_argv(show_workspace_config => 
            '--workspace' => $ws_name
        ),
        qr/modules_installed\s+:/,
        'show workspace config displays enabled plugins',
    );

    # Multi-plugin functionality is also exercised in plugin-pref.t
    expect_success(
        call_cli_argv(enable_plugin => qw(--all-workspaces --plugin all)),
        qr/The [-a-z]+ plugin is now enabled for all workspaces/,
        'enable all plugins on all workspaces works'
    );
}
