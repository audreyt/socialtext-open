#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences qw(eq_or_diff);
use Socialtext::Prefs::System;
use Socialtext::Prefs::Account;

fixtures('db');

my $account = create_test_account_bypassing_factory();
my $system_prefs = Socialtext::Prefs::System->new()->all_prefs;

instantiate: {
    my $acct = Socialtext::Prefs::Account->new(account=>$account);
    isa_ok $acct, 'Socialtext::Prefs::Account', 'got account prefs';

    eq_or_diff $acct->prefs, {}, 'account has no uninherited prefs';
    eq_or_diff $acct->all_prefs, $system_prefs,
        'inherits system prefs by default';
}

add_new_index: {
    my $acct_prefs = $account->prefs;
    my $prefs = { notify=>{key_one=>'value_one', key_two=>'value_two'} };

    ok $acct_prefs->save($prefs), 'saved prefs';
    eq_or_diff $acct_prefs->all_prefs, {%$system_prefs, %$prefs},
        'object cleaned up after save';

    my $freshened = Socialtext::Prefs::Account->new(account=>$account);
    isa_ok $freshened, 'Socialtext::Prefs::Account', 'got fresh prefs';
    eq_or_diff $acct_prefs->prefs, $prefs, 'added new index';
    eq_or_diff $acct_prefs->all_prefs, {%$system_prefs, %$prefs},
        'inherited prefs maintained';
}

override_system_prefs: {
    my $acct_prefs = $account->prefs;
    my $prefs = { timezone => {key_one=>'value_one', key_two=>'value_two'} };

    ok $acct_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::Account->new(account=>$account);
    isa_ok $freshened, 'Socialtext::Prefs::Account', 'got fresh prefs';
    eq_or_diff $freshened->prefs, {
        %$prefs, 
        notify => {key_one=>'value_one', key_two=>'value_two'},
    }, 'added new index';
    eq_or_diff $freshened->all_prefs, {
        %$prefs, 
        notify => {key_one=>'value_one', key_two=>'value_two'},
    }, 'overrode system prefs';
}

remove_an_index: {
    my $acct_prefs = $account->prefs;
    my $prefs = { notify => undef };

    ok $acct_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::Account->new(account=>$account);
    isa_ok $freshened, 'Socialtext::Prefs::Account', 'got fresh prefs';
    eq_or_diff $freshened->prefs, {
        timezone => {key_one=>'value_one', key_two=>'value_two'}
    }, 'index removed';
    eq_or_diff $freshened->all_prefs, {
        timezone => {key_one=>'value_one', key_two=>'value_two'}
    }, 'still overriding system prefs';
}

restore_system_defaults: {
    my $acct_prefs = $account->prefs;
    my $prefs = { timezone => undef };

    ok $acct_prefs->save($prefs), 'saved prefs';

    my $freshened = Socialtext::Prefs::Account->new(account=>$account);
    isa_ok $freshened, 'Socialtext::Prefs::Account', 'got fresh prefs';
    eq_or_diff $freshened->prefs, {}, 'removed all object prefs';
    eq_or_diff $freshened->all_prefs, $system_prefs, 'system prefs restored';
}

test_form_input: {
    my $acct_prefs = $account->prefs;
    my $data = {
        'timezone__time_display_12_24' => '12',
        'timezone__time_display_seconds-boolean' => '0',
        'timezone__timezone' => '-0800',
        'preferences_class_id' => 'timezone',
        'timezone__dst' => 'auto-us',
        'timezone__date_display_format' => 'mmm_d_yyyy',
        'account_id' => '2'
    };

    my $parsed = $acct_prefs->parse_form_data($data);

    eq_or_diff $parsed, {
        timezone => {
            time_display_12_24 => '12',
            time_display_seconds => '0',
            timezone => '-0800',
            dst => 'auto-us',
            date_display_format => 'mmm_d_yyyy',
        }
    }, 'properly parsed form data';
}

done_testing;
exit;
################################################################################
