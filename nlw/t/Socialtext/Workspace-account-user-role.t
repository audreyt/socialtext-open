#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
use Socialtext::Permission qw/ST_READ_PERM/;
use Socialtext::Role;

fixtures('db');

my $in_acct = create_test_account_bypassing_factory();
my $in_wksp = create_test_workspace(account => $in_acct);
my $other_acct = create_test_account_bypassing_factory();
my $other_wksp = create_test_workspace(account => $other_acct);
my $user = create_test_user(account => $in_acct);
$user->password('123456'); # needed to make sure user->is_authenticated

for my $wksp ($in_wksp, $other_wksp) {
    $wksp->permissions->add(
        permission => ST_READ_PERM,
        role => Socialtext::Role->AccountUser()
    );
}

################################################################################
# TEST: Account Users (authenticated users that share an account with the
# workpsace) have permission to read/self-join in a self-join workspace.
account_users: {
    my $checker = $in_wksp->permissions;

    ok $checker->user_can(user => $user, permission => ST_READ_PERM),
        'Account User can read self-join Workspace content';
}

################################################################################
# TEST: Authenticated Users cannot read/self-join a self-join workspace.
athenticated_users: {
    my $checker = $other_wksp->permissions;

    ok !$checker->user_can(user => $user, permission => ST_READ_PERM),
        'Authenticated User cannot read self-join Workspace content';
}
