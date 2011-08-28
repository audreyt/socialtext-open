#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 27;
use Test::Socialtext::Fatal;

fixtures('db');

# Create a dummy system account and user so as not to ruin future tests.
my $sys_acct = create_test_account_bypassing_factory();
my $guest    = create_test_user(is_system_created => 1, account => $sys_acct);
my $regular  = create_test_user(is_system_created => 0, account => $sys_acct);
my $member   = Socialtext::Role->Member();

ok !$sys_acct->has_user($guest), 'no role for guest in its primary acct';
ok $sys_acct->has_user($regular), 'role for regular user in its primary acct';

workspace: {
    my $ws = create_test_workspace;
    ok exception {
        $ws->add_user(user => $guest, role => $member)
    }, 'add system-user to a workspace dies';
    ok !$ws->has_user($guest), '... user was not added to workspace';
    ok !exception {
        $ws->add_user(user => $regular, role => $member)
    }, 'added regular user just fine';
    ok $ws->has_user($regular), '... user was added to workspace';

    my $auw = create_test_workspace(account => $sys_acct);
    ok !exception {
        $auw->add_account(account => $sys_acct, role => $member);
    }, 'add system account to workspace is fine';
    ok !$auw->has_user($guest),
        '... HOWEVER user was not added to workspace';
    ok $auw->has_user($regular),
        '... regular user is in there though';
}

account: {
    my $account = create_test_account_bypassing_factory();
    ok exception {
        $account->add_user(user => $guest, role => $member)
    }, 'add system-user to an account dies';
    ok !$account->has_user($guest, {direct=>1}),
        '... user was not added to account';
    ok !exception {
        $account->add_user(user => $regular, role => $member)
    }, 'add regular to an account lives';
    ok $account->has_user($regular, {direct=>1}), '... user was added to account';

    ok exception {
        $guest->primary_account($account->account_id)
    }, 'change a system-user primary account dies';
    ok !$account->has_user($guest, {direct=>1}),
        '... user role was not added to account';
    ok $guest->primary_account_id == $sys_acct->account_id,
        '... user primary account was not changed';
    ok !exception {
        $regular->primary_account($account->account_id)
    }, 'change a regular primary account lives';
    ok $account->has_user($regular, {direct=>1}),
        '... user role was added to account';
    ok $regular->primary_account_id == $account->account_id,
        '... user primary account was changed';
}

group: {
    my $group = create_test_group();
    ok exception {
        $group->add_user(user => $guest, role => $member)
    }, 'cannot add system-user to a group';
    ok !$group->has_user($guest, {direct=>1}),
        '... user was not added to group';
    ok !exception {
        $group->add_user(user => $regular, role => $member)
    }, 'can add system-user to a group';
    ok $group->has_user($regular, {direct=>1}),
        '... user was added to group';
}

sys_admin: {
    ok exception { $guest->set_business_admin(1) }, 'no bus admin';
    ok exception { $guest->set_business_admin(0) }, 'no bus admin';
    ok exception { $guest->set_technical_admin(1) }, 'no tech admin';
    ok exception { $guest->set_technical_admin(0) }, 'no tech admin';
}

