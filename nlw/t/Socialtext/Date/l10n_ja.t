#!perl
# @COPYRIGHT@
use strict;
use warnings;
use utf8;

use Test::Socialtext;
use Socialtext::Date::l10n;

my @locale = qw( ja );
my @date_key = ('unknown');
my %strftime_date_formats = ( 'mm_dd_jp'   => '%m月%d日',
                              'unknown' => '%Y-%m-%d',
);
my %date_map = ( 'mm_dd_jp' => 'yyyy_mm_dd_jp',
                 'unknown' => 'unknown',
                );

my @time_key = ('24_ja', 'unknown');
my %strftime_time_formats = ( '24_ja'   => '%H時%M分',
                              'unknown' => '%H:%M',
);

my %strftime_time_sec_formats = ( '24_ja'   => '%H時%M分%S秒',
                              'unknown' => '%H:%M:%S',
);

my @date_all_key = sort qw( default yyyy_mm_dd yyyy_mm_dd_sl yyyy_mm_dd_jp );
my @time_all_key = sort qw( default 24 12ampm 24_ja );

my $dt = DateTime->new(
        year => 2007,
        month => 3,
        day => 14,
        hour => 13,
        minute => 15,
        second => 30
);

my $test_num = @date_key + @date_key + @time_key + @time_key + 2;
plan tests => $test_num * @locale;

foreach( @locale ) {
    run_tests( $_ );
}

sub run_tests {
    my $locale = shift;

get_formated_date: {
    foreach( @date_key ) {
        my $date = Socialtext::Date::l10n->get_formated_date($dt, $_, $locale);
        is $date, $dt->clone->strftime( $strftime_date_formats{ $_ } ), "get_formated_date: key = " . $_ . ", locale = " . $locale;
    }
}

get_date_to_year_key_map: {
    foreach( @date_key ) {
        my $newkey = Socialtext::Date::l10n->get_date_to_year_key_map($_, $locale);
        is $newkey, $date_map{ $_ }, "get_date_to_year_key_map: key = " . $_ . ", locale = " . $locale;
    }
}

get_formated_time: {
    foreach( @time_key ) {
        my $time = Socialtext::Date::l10n->get_formated_time($dt, $_, $locale);
        is $time, $dt->clone->strftime( $strftime_time_formats{ $_ } ), "get_formated_time: key = " . $_ . ", locale = " . $locale;
    }
}

get_formated_time_sec: {
    foreach( @time_key ) {
        my $time = Socialtext::Date::l10n->get_formated_time_sec($dt, $_, $locale);
        is $time, $dt->clone->strftime( $strftime_time_sec_formats{ $_ } ), "get_formated_time_sec: key = " . $_ . ", locale = " . $locale;
    }
}

get_all_format_date: {
    my @keys = Socialtext::Date::l10n->get_all_format_date($locale);
    my @sorted_keys = sort @keys;
    is "@sorted_keys", "@date_all_key", "get_all_format_date: locale = " . $locale;
}

get_all_format_time: {
    my @keys = Socialtext::Date::l10n->get_all_format_time($locale);
    my @sorted_keys = sort @keys;
    is "@sorted_keys", "@time_all_key", "get_all_format_time: locale = " . $locale;
}

}

