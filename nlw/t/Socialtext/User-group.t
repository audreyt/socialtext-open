#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 12;
use Test::Differences;

fixtures(qw/db/);

use_ok 'Socialtext::User';

user_has_no_groups: {
    my $me = create_test_user();
    my $groups = $me->groups;

    isa_ok $groups, 'Socialtext::MultiCursor', 'got a list of groups';
    is $groups->count(), 0, '... with the correct count';
}

user_has_groups: {
    my $me        = create_test_user();
    my $group_one = create_test_group();
    my $group_two = create_test_group();

    $group_one->add_user(user => $me);
    $group_two->add_user(user => $me);

    my $groups = $me->groups();
    isa_ok $groups, 'Socialtext::MultiCursor', 'got a list of groups';
    is $groups->count(), 2, '... with the correct count';
    isa_ok $groups->next(), 'Socialtext::Group', '...';
}

accounts_and_groups: {
    my $acct_zero = create_test_account_bypassing_factory("ZZZ$^T");
    my $acct_one  = create_test_account_bypassing_factory("AAA$^T");
    my $acct_two  = create_test_account_bypassing_factory("BBB$^T");
    my $user      = create_test_user(account => $acct_zero);
    my $group_one = create_test_group(account => $acct_one, unique_id => "GGG$^T");
    my $group_two = create_test_group(account => $acct_two, unique_id => "FFF$^T");

    $_->enable_plugin('test') for ($acct_zero,$acct_one,$acct_two);

    $group_one->add_user(user => $user);
    $acct_two->add_group(group => $group_one);
    $group_two->add_user(user => $user);

    my ($accts,$acct_group_set,$group_count) =
        $user->accounts_and_groups(plugin => 'test');

    is $group_count, 3;
    eq_or_diff [map {$_->account_id} @{$accts||[]}],
               [map {$_->account_id} $acct_one,$acct_two,$acct_zero],
               "got all accounts for this user";

    for my $val (values %$acct_group_set) {
        @$val = map { 0+$_->group_id } @$val;
    }
    eq_or_diff 
        $acct_group_set,
        {
            $acct_one->account_id => [
                $group_one->group_id,
            ],
            $acct_two->account_id => [
                $group_two->group_id,
                $group_one->group_id,
            ],
            $acct_zero->account_id => [],
        },
        "the groups are batched and ordered correctly";

    $acct_one->disable_plugin('test');
    ($accts,$acct_group_set,$group_count) =
        $user->accounts_and_groups(plugin => 'test');

    is $group_count, 2;
    eq_or_diff [map {$_->account_id} @{$accts||[]}],
               [map {$_->account_id} $acct_two,$acct_zero],
               "accounts reduced after disabling plugin";

    for my $val (values %$acct_group_set) {
        @$val = map { 0+$_->group_id } @$val;
    }
    eq_or_diff 
        $acct_group_set,
        {
            $acct_two->account_id => [
                $group_two->group_id,
                $group_one->group_id,
            ],
            $acct_zero->account_id => [],
        },
        "the groups are batched and ordered correctly";

}
