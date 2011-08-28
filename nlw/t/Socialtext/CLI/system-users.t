#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 7;
use Test::Socialtext::CLIUtils qw/:all/;

fixtures(qw(db));

my $acct = create_test_account_bypassing_factory();
my $user = create_test_user(account => $acct, is_system_created => 1);
ok $user && $user->is_system_created, 'made a system user';
my $regular = create_test_user(account => $acct);
ok $regular && !$regular->is_system_created, 'made a regular user';

cant_change_password: {
    expect_success(
        call_cli_argv(
            qw(change-password --username), $regular->username,
            qw(--password p4ssw0rd)
        ), qr/has been changed/, 'can change password of regular user'
    );

    expect_failure(
        call_cli_argv(
            qw(change-password --username), $user->username,
            qw(--password p4ssw0rd)
        ), qr/cannot change/, 'cannot change password of sys user'
    );
}

pass 'done';
