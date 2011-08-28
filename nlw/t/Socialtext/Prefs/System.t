#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences qw(eq_or_diff);
use Guard qw(scope_guard);

use Socialtext::Prefs::System;

fixtures('db');

instantiate: {
    my $system_prefs = Socialtext::Prefs::System->new();
    isa_ok $system_prefs, 'Socialtext::Prefs::System', 'got a prefs object';

    eq_or_diff $system_prefs->prefs, {}, 'non default prefs are empty';
    eq_or_diff $system_prefs->all_prefs, {
        timezone => {
            timezone => '-0800',
            dst => 'auto-us',
            date_display_format => 'mmm_d_yyyy',
            time_display_12_24 => '12',
            time_display_seconds => '0',
        },
    }, 'correct default system prefs for en locale';
}

non_en_locale: {
    my $guard = scope_guard { set_locale('en') };
    set_locale('zh_TW');
    
    my $system_prefs = Socialtext::Prefs::System->new();

    eq_or_diff $system_prefs->prefs, {}, 'non default prefs are empty';
    eq_or_diff $system_prefs->all_prefs, {
        timezone => {
            timezone => '-0800',
            dst => 'never',
            date_display_format => 'yyyy_mm_dd',
            time_display_12_24 => '24',
            time_display_seconds => '0',
        },
    }, 'correct default system prefs for zh_TW locale';
}

save: {
    my $system_prefs = Socialtext::Prefs::System->new();
    my $prefs = {
        timezone => {
            timezone => 'one',
            dst => 'twp',
            date_display_format => 'three',
            time_display_12_24 => 'four',
            time_display_seconds => 'five',
        },
    };
    ok $system_prefs->save($prefs), 'saved system prefs';

    my $freshened = Socialtext::Prefs::System->new();
    eq_or_diff $freshened->all_prefs, $prefs, 'system all_prefs updated';
    eq_or_diff $freshened->prefs, $prefs, 'system prefs updated';
}

back_to_locale_defaults: {
    my $system_prefs = Socialtext::Prefs::System->new();
    ok $system_prefs->save({timezone => undef}), 'saved system prefs';

    my $freshened = Socialtext::Prefs::System->new();

    eq_or_diff $freshened->prefs, {}, 'non default prefs are empty again';
    eq_or_diff $system_prefs->all_prefs, {
        timezone => {
            timezone => '-0800',
            dst => 'auto-us',
            date_display_format => 'mmm_d_yyyy',
            time_display_12_24 => '12',
            time_display_seconds => '0',
        },
    }, 'locale defaults restored';
}

done_testing;
exit;
################################################################################

sub set_locale {
    Socialtext::AppConfig->set(locale => shift);
    Socialtext::AppConfig->write();
}
