#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 61;
use Test::Differences;
use List::MoreUtils qw/all none/;
use Scalar::Util qw/blessed/;

fixtures('db');

my $Admin = Socialtext::Role->Admin;
my $Admin_id = $Admin->role_id;
my $Member = Socialtext::Role->Member;
my $Member_id = $Member->role_id;
ok $Member_id < $Admin_id, "admin comes after member";

my $b_pri = create_test_account_bypassing_factory("B Acct $^T");
my $a_pri = create_test_account_bypassing_factory("A Acct $^T");

my $group = create_test_group(unique_id => "ZZZGROUP$^T", account => $b_pri);
my $user1 = create_test_user(unique_id => "ZZZ$^T");
my $uid1 = $user1->user_id;
$group->add_user(user => $user1);
my $user2 = create_test_user(unique_id => "AAA$^T");
my $uid2 = $user2->user_id;
$group->add_user(user => $user2);
my $user3 = create_test_user(unique_id => "MMM$^T");
my $uid3 = $user3->user_id;
$group->add_user(user => $user3);

# nested
my $group2 = create_test_group(unique_id => "AAAGROUP$^T", account => $a_pri);
$group->add_group(group => $group2, role => 'admin');

# an indirect+direct user
my $user4 = create_test_user(unique_id => "JJJ$^T");
my $uid4 = $user4->user_id;
$group2->add_user(user => $user4, role => 'admin');
$group->add_user(user => $user4, role => 'member');

# an indirect-only user
my $user5 = create_test_user(unique_id => "PPP$^T");
my $uid5 = $user5->user_id;
$group2->add_user(user => $user5, role => 'admin');

# an account-only user
my $user6 = create_test_user(unique_id => "QQQ$^T");
my $uid6 = $user6->user_id;

# empty group
my $group3 = create_test_group(unique_id => "NNNGROUP$^T", account => $b_pri);

# empty nesting group
my $group4 = create_test_group(unique_id => "WWWGROUP$^T", account => $a_pri);
$group4->add_group(group => $group3, role => $Member);

my $acct = create_test_account_bypassing_factory("Z Acct $^T");
$acct->add_group(group => $_, role => $Member)
    for ($group,$group2,$group3);
$acct->add_group(group => $group4, role => $Admin);
$acct->add_user(user => $user6, role => $Admin);

sorted_users: {
    my $cursor = $group->sorted_user_roles(
        order_by => 'username',
        sort_order => 'asc',
        raw => 1,
        direct => 1,
    );
    is $cursor->count, 4;
    my @all = $cursor->all();
    is_deeply [ map {$_->{user_id}} @all ], [$uid2,$uid4,$uid3,$uid1];
    ok none(sub { exists $_->{user} }, @all), "no user objects";
    ok none(sub { exists $_->{role} }, @all), "no role objects";
    ok none(sub { exists $_->{group} }, @all), "no group objects";
    ok all(sub { $_->{role_id} == $Member->role_id }, @all), "all members";
    ok none(sub { $_->{user_id} == $uid5 }, @all), "indirect-only user excluded";
    ok all(sub { $_->{group_id} == $group->group_id }, @all), "all in this group";

    $cursor = $group->sorted_user_roles(
        order_by => 'username',
        sort_order => 'asc',
        raw => 1,
    );
    is $cursor->count, 6;
    @all = $cursor->all();
    ok none(sub { exists $_->{user} }, @all), "no user objects";
    ok none(sub { exists $_->{role} }, @all), "no role objects";
    ok none(sub { exists $_->{group} }, @all), "no group objects";
    is_deeply [ map {$_->{user_id}} @all ], [
        $uid2,$uid4,$uid4,$uid3,$uid5,$uid1];
    is_deeply [ map {$_->{role_id}} @all ], [
        $Member_id,$Member_id,$Admin_id,$Member_id,$Admin_id,$Member_id];

    $cursor = $group->sorted_user_roles(
        order_by => 'role_name',
        sort_order => 'asc',
        raw => 1,
    );
    is $cursor->count, 6;
    @all = $cursor->all();
    ok none(sub { exists $_->{user} }, @all), "no user objects";
    ok none(sub { exists $_->{role} }, @all), "no role objects";
    ok none(sub { exists $_->{group} }, @all), "no group objects";
    is_deeply [ map {$_->{role_id}} @all ], [
        ($Admin_id) x 2, ($Member_id) x 4], 'role_name major sort';
    is_deeply [ map {$_->{user_id}} @all ], [
        $uid4,$uid5,$uid1,$uid2,$uid3,$uid4], 'uids minor sort';

    $cursor = $group->sorted_user_roles(
        order_by => 'username',
        sort_order => 'desc',
        direct => 1,
    );
    is $cursor->count, 4, 'username desc';
    @all = $cursor->all();
    ok all(sub { blessed $_->{user} }, @all), "lots of user objects";
    ok all(sub { blessed $_->{role} }, @all), "lots of role objects";
    ok all(sub { blessed $_->{group} }, @all), "lots of group objects";
    is_deeply [ map {$_->{user}->user_id} @all ], [$uid1,$uid3,$uid4,$uid2],
        "mapped by user_id method";

    $cursor = $group->sorted_user_roles(
        order_by => 'source',
        sort_order => 'desc',
        raw => 1,
    );
    is $cursor->count, 6;
    @all = $cursor->all();
    ok none(sub { exists $_->{user} }, @all), "no user objects";
    ok none(sub { exists $_->{role} }, @all), "no role objects";
    ok none(sub { exists $_->{group} }, @all), "no group objects";
    is_deeply [ map {$_->{user_id}} @all ], [
        $uid1,$uid2,$uid3,$uid4,$uid4,$uid5], 'uids minor sort; all same source';
}

sorted_users_on_an_account: {
    my $cursor = $acct->sorted_user_roles(
        order_by => 'display_name',
        sort_order => 'asc',
        raw => 1,
    );
    is $cursor->count, 6;
    my @all = $cursor->all();
    is_deeply [ map {$_->{user_id}} @all ], [
        $uid2,$uid4,$uid3,$uid5,$uid6,$uid1], 'sorted users on account';

    $cursor = $acct->sorted_user_roles(
        order_by => 'display_name',
        sort_order => 'desc',
        raw => 1,
    );
    is $cursor->count, 6;
    @all = $cursor->all();
    is_deeply [ map {$_->{user_id}} @all ], [
        $uid1,$uid6,$uid5,$uid3,$uid4,$uid2], 'sorted users on account';
}

sorted_groups_on_an_account: {
    my $cursor = $acct->sorted_group_roles(
        order_by => 'display_name',
        raw => 1,
        direct => 1,
    );
    is $cursor->count, 4, 'sorted groups by name on account';
    my @all = $cursor->all();
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group2, $group3, $group4, $group];
    eq_or_diff [ map {$_->{role_id}} @all ], [
        $Member_id, $Member_id, $Admin_id, $Member_id];

    $cursor = $acct->sorted_group_roles(
        order_by => 'role',
        raw => 1,
    );
    is $cursor->count, 5, 'sorted groups by role-name on account';
    @all = $cursor->all();
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group3, $group4, $group, $group2, $group3];
    eq_or_diff [ map {$_->{role_id}} @all ], [
        ($Admin_id) x 2, ($Member_id) x 3];

    $cursor = $acct->sorted_group_roles(
        order_by => 'source',
    );
    is $cursor->count, 5, 'sorted groups by source on account';
    @all = $cursor->all();
    ok all(sub { blessed($_->{account}) }, @all), 'all entries have an account';
    ok all(sub { blessed($_->{group}) }, @all), 'all entries have a group';
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group, $group2, $group3, $group3, $group4];
    eq_or_diff [ map {$_->{role_id}} @all ], [
        ($Member_id) x 3, ($Admin_id) x 2];

    $cursor = $acct->sorted_group_roles();
    is $cursor->count, 5, 'sorted groups by default subsort on account';
    @all = $cursor->all();
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group, $group2, $group3, $group3, $group4];
    eq_or_diff [ map {$_->{role_id}} @all ], [
        ($Member_id) x 3, ($Admin_id) x 2];

    $cursor = $acct->sorted_group_roles(
        order_by => 'account',
        sort_order => 'desc',
    );
    is $cursor->count, 5, 'sorted groups by account on account';
    @all = $cursor->all();
    eq_or_diff [ map {$_->{account_name}} @all ], [
        ($b_pri->name) x 3, ($a_pri->name) x 2 ];
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group, $group3, $group3, $group2, $group4];

    $cursor = $acct->sorted_group_roles(
        order_by => 'display_name',
        raw => 1,
        mux_roles => 1,
    );
    is $cursor->count, 4, 'sorted groups by name on account, mux roles';
    @all = $cursor->all();
    eq_or_diff [ map {$_->{group_id}} @all ], [ map { $_->group_id }
        $group2, $group3, $group4, $group];
    eq_or_diff [ map {$_->{role_ids}} @all ], [
        [$Member_id], [$Member_id,$Admin_id], [$Admin_id], [$Member_id]];
}

accounts_for_group: {
    my $cursor = $group3->sorted_account_roles(
        order_by => 'account',
    );
    my @all = $cursor->all();
    is $cursor->count, 4, 'sorted accounts related to a group';
    ok all(sub { blessed($_->{account}) }, @all), 'all entries have an account';
    ok all(sub { blessed($_->{group}) }, @all), 'all entries have a group';
    ok all(sub { blessed($_->{role}) }, @all), 'all entries have a role';
    eq_or_diff [ map {$_->{account_name}} @all ], [
        $a_pri->name, $b_pri->name, ($acct->name) x 2];
}

pass 'done';
