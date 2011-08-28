#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Cwd;
use File::Path qw(rmtree);
use File::Spec;
use File::Temp qw(tempdir);
use Test::Socialtext tests => 20;
use Socialtext::CLI;
use Socialtext::SQL qw(:exec);
use Test::Socialtext::CLIUtils qw(expect_success expect_failure);

# Fixtures: db
fixtures(qw( db ));

# Tests for `st-admin set-plugin-pref`

Clear_all_prefs: {
    sql_execute('DELETE FROM plugin_pref');
}

Set_pref: {
    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test key value)] )
                ->set_plugin_pref();
        },
        qr/Preferences for the test plugin\(s\) have been updated./,
        'set-plugin-pref',
    );
}

Set_pref_multi_plugin: {
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [qw(--plugin test --plugin default key value)]
            )->set_plugin_pref();
        },
        qr/Preferences for the default, test plugin\(s\) have been updated./,
        'set-plugin-pref multi-plugin',
    );
}

Set_pref_all_plugin: {
    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [qw(--plugin all key value)]
            )->set_plugin_pref();
        },
        qr/Preferences for the [a-z,\s]+ plugin\(s\) have been updated./,
        'set-plugin-pref multi-plugin',
    );
}

Get_prefs: {
    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test)])
                ->show_plugin_prefs();
        },
        qr/Preferences for the test plugin:.+key\s=>\svalue/s,
            'show-plugin-prefs',
    );
}

Get_prefs_accepts_single_plugin: {
    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [qw(--plugin test --plugin default)]
            )->show_plugin_prefs();
        },
        qr/show-plugin-prefs only works on a single plugin/,
        'show-plugin-prefs with multiple --plugin',
    );

    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [qw(--plugin all)]
            )->show_plugin_prefs();
        },
        qr/show-plugin-prefs only works on a single plugin/,
        'show-plugin-prefs with all plugins',
    );
}

Set_another_pref: {
    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test ape monkey)] )
                ->set_plugin_pref();
        },
        qr/Preferences for the test plugin\(s\) have been updated./,
        'set-plugin-pref',
    );
}

Get_prefs: {
    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test)])
                ->show_plugin_prefs();
        },
        qr/Preferences for the test plugin:.+ape => monkey.+key => value/s,
            'show-plugin-prefs',
    );
}

Clear_prefs: {
    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test)] )
                ->clear_plugin_prefs();
        },
        qr/Preferences for the test plugin\(s\) have been cleared./,
        'clear-plugin-prefs',
    );

    expect_success(
        sub {
            Socialtext::CLI->new( argv => [qw(--plugin test)])
                ->show_plugin_prefs();
        },
        qr/No preferences set for the test plugin./,
            'show-plugin-prefs',
    );
}

exit;

# bad plugin
