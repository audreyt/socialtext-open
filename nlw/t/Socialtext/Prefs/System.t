#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences qw(eq_or_diff);
use Guard qw(scope_guard);

use Socialtext::Prefs::System;

fixtures('db');

my $theme_keys = [ qw(background_color background_image_id
    background_image_position background_image_tiling background_link_color
    base_theme_id body_font favicon_image_id foreground_shade header_color
    header_font header_image_id header_image_position header_image_tiling
    header_link_color logo_image_id primary_color secondary_color
    tertiary_color
) ];

instantiate: {
    my $system_prefs = Socialtext::Prefs::System->new();
    isa_ok $system_prefs, 'Socialtext::Prefs::System', 'got a prefs object';

    eq_or_diff $system_prefs->prefs, {}, 'non default prefs are empty';
    my $all_prefs = $system_prefs->all_prefs;

    ok $all_prefs->{timezone}, 'have a timezone index';
    eq_or_diff $all_prefs->{timezone}, {
        timezone => '-0800',
        dst => 'auto-us',
        date_display_format => 'mmm_d_yyyy',
        time_display_12_24 => '12',
        time_display_seconds => '0',
    }, 'correct default timezone prefs for en locale';

    ok $all_prefs->{theme}, 'have a theme index';
    eq_or_diff [ sort keys %{$all_prefs->{theme}} ], $theme_keys,
        'correct default theme prefs for en locale';
    
}

non_en_locale: {
    my $guard = scope_guard { set_locale('en') };
    set_locale('zh_TW');
    
    my $system_prefs = Socialtext::Prefs::System->new();
    eq_or_diff $system_prefs->prefs, {}, 'non default prefs are empty';
    my $all_prefs = $system_prefs->all_prefs;

    ok $all_prefs->{timezone}, 'have a timezone index';
    eq_or_diff $all_prefs->{timezone}, {
        timezone => '-0800',
        dst => 'never',
        date_display_format => 'yyyy_mm_dd',
        time_display_12_24 => '24',
        time_display_seconds => '0',
    }, 'correct default timezone prefs for zh_TW locale';

    ok $all_prefs->{theme}, 'have a theme index';
    eq_or_diff [ sort keys %{$all_prefs->{theme}} ], $theme_keys,
        'correct default theme prefs for zh_TW locale';
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
    my $all_prefs = $freshened->all_prefs;

    ok $all_prefs->{theme}, 'have a theme index in all_prefs';
    eq_or_diff [ sort keys %{$all_prefs->{theme}} ], $theme_keys,
        'correct theme prefs in all_prefs';

    ok $all_prefs->{timezone}, 'have a timezone index in all_prefs';
    eq_or_diff $all_prefs->{timezone}, $prefs->{timezone},
        'system all_prefs updated';
    eq_or_diff $freshened->prefs, $prefs, 'system prefs updated';
}

back_to_locale_defaults: {
    my $system_prefs = Socialtext::Prefs::System->new();
    ok $system_prefs->save({timezone => undef}), 'saved system prefs';

    my $freshened = Socialtext::Prefs::System->new();

    eq_or_diff $freshened->prefs, {}, 'non default prefs are empty again';
    my $all_prefs = $freshened->all_prefs;

    ok $all_prefs->{theme}, 'have a theme index in all_prefs';
    eq_or_diff [ sort keys %{$all_prefs->{theme}} ], $theme_keys,
        'correct theme prefs in all_prefs';

    ok $all_prefs->{timezone}, 'have a timezone index in all_prefs';
    eq_or_diff $all_prefs->{timezone}, {
        timezone => '-0800',
        dst => 'auto-us',
        date_display_format => 'mmm_d_yyyy',
        time_display_12_24 => '12',
        time_display_seconds => '0',
    }, 'locale defaults restored';
}

done_testing;
exit;
################################################################################

sub set_locale {
    Socialtext::AppConfig->set(locale => shift);
    Socialtext::AppConfig->write();
}
