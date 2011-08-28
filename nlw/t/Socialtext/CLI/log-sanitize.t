#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 12;
use Socialtext::CLI;
use Test::Socialtext::CLIUtils qw(expect_success call_cli_argv);

fixtures(qw( db ));

###############################################################################
# TEST: Don't log passwords; short-hand
dont_log_passwords_short: {
    my $email = "short-hand-$$\@null.socialtext.net";
    clear_log();

    expect_success(
        call_cli_argv( 'create-user' =>
            '-e' => $email,
            '-p' => 'abc123',
        ),
        qr/A new user.*was created/,
        'Test User created',
    );

    logged_like 'info', qr/CLI,CREATE-USER.*"args":"create-user -e $email -p xxxxxx/,
        '... log entry sanitized';
    logged_not_like 'info', qr/abc123/,
        '... and no log entry contained the original password';
}

###############################################################################
# TEST: Don't log passwords; long-hand
dont_log_passwords_long: {
    my $email = "long-hand-$$\@null.socialtext.net";
    clear_log();

    expect_success(
        call_cli_argv( 'create-user' =>
            '--email'    => $email,
            '--password' => 'abc123',
        ),
        qr/A new user.*was created/,
        'Test User created',
    );

    logged_like 'info',
        qr/CLI,CREATE-USER.*"args":"create-user --email $email --password xxxxxx/,
        '... log entry sanitized';
    logged_not_like 'info', qr/abc123/,
        '... and no log entry contained the original password';
}

###############################################################################
# TEST: Don't log passwords; short-long-hand
dont_log_passwords_short_long: {
    my $email = "short-long-hand-$$\@null.socialtext.net";
    clear_log();

    expect_success(
        call_cli_argv( 'create-user' =>
            '--e' => $email,
            '--p' => 'abc123',
        ),
        qr/A new user.*was created/,
        'Test User created',
    );

    logged_like 'info',
        qr/CLI,CREATE-USER.*"args":"create-user --e $email --p xxxxxx/,
        '... log entry sanitized';
    logged_not_like 'info', qr/abc123/,
        '... and no log entry contained the original password';
}
