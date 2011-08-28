#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 26;
fixtures('db');

BEGIN {
    use_ok 'Socialtext::User';
    use_ok 'Socialtext::Account';
}

my $acct_a = create_test_account_bypassing_factory();
$acct_a->enable_plugin('test');
my $user = create_test_user(account => $acct_a);

Check_just_one_account: {
    my @acct_list = $user->accounts();
    is scalar(@acct_list), 1, "just one account";
    isa_ok $acct_list[0], 'Socialtext::Account';
    is_deeply [ map {$_->account_id} @acct_list ],
              [ map {$_->account_id} $acct_a ];
}

my $acct_b = create_test_account_bypassing_factory();
$acct_b->enable_plugin('test');
my $ws_b = create_test_workspace(account => $acct_b);
$ws_b->add_user(user=>$user);

Two_accounts_now: {
    is $user->primary_account_id, $acct_a->account_id;
    my @acct_list = $user->accounts();
    is scalar(@acct_list), 2, 'two accounts now';
    is_deeply [ map {$_->account_id} @acct_list ],
              [ map {$_->account_id} $acct_a, $acct_b ];
}

test_plugin_associations: {
    $acct_a->disable_plugin('test');
    $acct_b->disable_plugin('test');

    no_plugin_association: {
        my $acct_list = $user->accounts(plugin => 'test');
        is_deeply $acct_list, [], 'no accounts for "test" plugin';
    }

    $acct_a->enable_plugin('test');

    one_plugin_association: {
        my @acct_list = $user->accounts(plugin => 'test');
        is scalar(@acct_list), 1, 'two accounts now';
        is_deeply [ map {$_->account_id} @acct_list ],
                  [ map {$_->account_id} $acct_a ];
    }

    $acct_b->enable_plugin('test');

    two_plugin_associations: {
        is $user->primary_account_id, $acct_a->account_id;
        my @acct_list = $user->accounts(plugin => 'test');
        is scalar(@acct_list), 2, 'two accounts again';
        is_deeply [ map {$_->account_id} @acct_list ],
                  [ map {$_->account_id} $acct_a, $acct_b ];
    }
}

$acct_a->assign_role_to_user(user => $user, role => 'admin');
$user->primary_account($acct_b);

Retains_old_primary_account_role: {
    is $user->primary_account_id, $acct_b->account_id;
    my @acct_list = $user->accounts();
    is scalar(@acct_list), 2, 'retains old primary acct';
    is_deeply [ map {$_->account_id} @acct_list ],
              [ map {$_->account_id} $acct_a, $acct_b ];

    my $new_role = $acct_a->role_for_user($user, direct => 1);
    is $new_role->name, 'admin', 'retained admin role';
    my $new_role_b = $acct_b->role_for_user($user, direct => 1);
    is $new_role_b->name, 'member', 'new account role is member';
}

$acct_a->remove_user(user => $user);
Back_to_one_account: {
    my @acct_list = $user->accounts();
    is scalar(@acct_list), 1, 'back to one account';
    is_deeply [ map {$_->account_id} @acct_list ],
              [ map {$_->account_id} $acct_b ];
}

shares_account: {
    my $acct_c = create_test_account_bypassing_factory();
    $acct_c->enable_plugin('test');
    my $user_b = create_test_user(account => $acct_b);
    my $user_c = create_test_user(account => $acct_c);

    ok $user->shares_account(intersect_with => $user_b->user_id), 'Users A & B share an account';
    ok $user_b->shares_account(intersect_with => $user->user_id), 'Users B & A share an account';
    ok !$user->shares_account(intersect_with => $user_c->user_id), 'Users A & C do not share an account';
    ok !$user_c->shares_account(intersect_with => $user->user_id), 'Users C & A do not share an account';

}

pass 'done';
