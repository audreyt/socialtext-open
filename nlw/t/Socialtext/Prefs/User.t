#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences qw(eq_or_diff);
use Socialtext::Prefs::User;
use Socialtext::Prefs::Account;

fixtures('db');

my $account = create_test_account_bypassing_factory();
my $user = create_test_user(account=>$account);
my $acct_prefs = $account->prefs->all_prefs;

instantiate: {
    my $user_prefs = $user->prefs;
    isa_ok $user_prefs, 'Socialtext::Prefs::User', 'got a prefs object';

    eq_or_diff $user_prefs->prefs, {}, 'user prefs are empty';
    eq_or_diff $user_prefs->all_prefs, $acct_prefs, 'inheriting account prefs';
}

add_new_index: {
    my $user_prefs = $user->prefs;
    my $prefs = { notify=>{key_one=>'value_one', key_two=>'value_two'} };

    ok $user_prefs->save($prefs), 'saved prefs by updating prefs attribute';
    eq_or_diff $user_prefs->all_prefs, {%$acct_prefs, %$prefs},
        'object cleaned up after save';

    my $freshened = Socialtext::Prefs::User->new(user=>$user);
    isa_ok $freshened, 'Socialtext::Prefs::User', 'got a fresh prefs object';
    eq_or_diff $freshened->prefs, $prefs, 'added new index';
    eq_or_diff $freshened->all_prefs, {%$acct_prefs, %$prefs},
        'inherited prefs maintained';
}

override_inherited_prefs: {
    my $user_prefs = $user->prefs;
    my $prefs = { timezone => {key_one=>'value_one', key_two=>'value_two'} };

    ok $user_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::User->new(user=>$user);
    isa_ok $freshened, 'Socialtext::Prefs::User', 'got a fresh prefs object';
    eq_or_diff $freshened->prefs, {
        %$prefs,
        notify=>{key_one=>'value_one', key_two=>'value_two'},
    }, 'added new index';
    eq_or_diff $freshened->all_prefs, {
        %$prefs,
        notify=>{key_one=>'value_one', key_two=>'value_two'},
    }, 'overrode inherited prefs';
}

remove_an_index: {
    my $user_prefs = $user->prefs;
    my $prefs = { notify=>undef };

    ok $user_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::User->new(user=>$user);
    isa_ok $freshened, 'Socialtext::Prefs::User', 'got a fresh prefs object';
    eq_or_diff $freshened->prefs, {
        timezone => {key_one=>'value_one', key_two=>'value_two'},
    }, 'index removed';
    eq_or_diff $freshened->all_prefs, {
        timezone => {key_one=>'value_one', key_two=>'value_two'},
    }, 'still overriding inherited prefs';
}

restore_inherited_prefs: {
    my $user_prefs = $user->prefs;
    my $prefs = { timezone=>undef };

    ok $user_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::User->new(user=>$user);
    isa_ok $freshened, 'Socialtext::Prefs::User', 'got a fresh prefs object';
    eq_or_diff $freshened->prefs, {}, 'removed all object prefs';
    eq_or_diff $freshened->all_prefs, $acct_prefs,
        'inherited prefs restored';
}

done_testing;
exit;
################################################################################
