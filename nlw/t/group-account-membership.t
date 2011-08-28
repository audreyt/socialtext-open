#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

# This test asserts that API activity matches up with group_account_role table
# contents.

use Test::Socialtext tests => 15;
use Socialtext::SQL qw/:exec/;
use Socialtext::Group;
use Socialtext::Account;
use Socialtext::Workspace;
use Socialtext::Role;
use Socialtext::Pluggable::Adapter;

fixtures( 'db' );

sub account_role_count_is ($$;$) {
    my $acct = shift;
    my $expected = shift;
    my $comment = shift;

    my $count = sql_singlevalue(q{
        SELECT COUNT(*)
          FROM user_set_path
         WHERE into_set_id = ?
    }, $acct->user_set_id);

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is $count, $expected, $comment;
}

sub check_group_account_role($$;$$) {
    my $group   = shift;
    my $account = shift || Socialtext::Account->Default;
    my $role    = shift || Socialtext::Role->Member;
    my $comment = shift;

    $role = Socialtext::Role->new(name => lc $role) unless ref($role);

    my $role_id = sql_singlevalue(q{
        SELECT role_id
          FROM user_set_path
         WHERE from_set_id = ? AND into_set_id = ?
         LIMIT 1
    }, $group->user_set_id, $account->user_set_id);

    my $actual_role = Socialtext::Role->new(role_id => $role_id);
    my $actual_name = $actual_role ? $actual_role->name : 'no-role';

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is $actual_name => $role->name, $comment;
}

# watch account membership as we add and remove a group to/from an account
via_direct_roles: {
    my $acct = create_test_account_bypassing_factory();
    my $group = create_test_group(); # some other primary account
    my $group2 = create_test_group(); # some other primary account

    account_role_count_is $acct => 0, "no roles initially";

    my $role = Socialtext::Role->Member;
    $acct->add_group(group => $group, role => $role);
    $acct->add_group(group => $group2, role => $role);

    account_role_count_is $acct => 2, "two new roles";
    check_group_account_role $group, $acct;
    check_group_account_role $group2, $acct;

    $acct->remove_group(group => $group);
    $acct->remove_group(group => $group2);

    account_role_count_is $acct => 0, "no roles after deletion";
}

# account membership is set up when Group is created
via_primary_account: {
    my $acct  = create_test_account_bypassing_factory();
    my $acct2 = create_test_account_bypassing_factory();
    my $group = create_test_group(account => $acct);

    $acct2->add_group(group => $group);

    account_role_count_is $acct => 1;
    check_group_account_role $group, $acct, 'Member',
        "primary account is Member relationship";

    account_role_count_is $acct2 => 1;
    check_group_account_role $group, $acct2, 'Member',
        "secondary account is Member relationship";

    $acct2->remove_group(group => $group);

    account_role_count_is($acct => 1, "member role retained");
    account_role_count_is($acct2 => 0, "member role removed");
}

# watch account membership as we add and remove a group to/from a workspace
via_workspace: {
    my $acct = create_test_account_bypassing_factory();
    my $ws = create_test_workspace(account => $acct);
    my $group = create_test_group(); # some other account

    account_role_count_is $acct => 1, "only workspace role initially";

    $ws->add_group(group => $group, role => 'admin');

    account_role_count_is $acct => 2;
    check_group_account_role $group, $acct, 'member',
        "group is a member through the workspace";

    $ws->remove_group(group => $group);

    account_role_count_is $acct => 1, 
        "removing group workspace role removes the member role";
}
