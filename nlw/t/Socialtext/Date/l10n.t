#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext;
use Socialtext::Date::l10n;

my @locale = qw( en unknown );
my @date_key = ('unknown');
my %strftime_date_formats = ( 'mm_dd'   => '%m-%d',
                              'unknown' => '%b %{day}, %Y',
);
my %date_map = ( 'mm_dd' => 'yyyy_mm_dd',
                 'unknown' => 'unknown',
                );

my @time_key = ('24', 'unknown');
my %strftime_time_formats = ( '24'   => '%H:%M',
                              'unknown' => '%l:%M%P',
);

my %strftime_time_sec_formats = ( '24'   => '%H:%M:%S',
                              'unknown' => '%l:%M:%S%P',
);

my @date_all_key = sort qw( default mmm_d_yyyy d_mmm_yy yyyy_mm_dd );
my @time_all_key = sort qw( default 24 12 );

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

foreach( @locale )
{
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
    is "@sorted_keys", "@date_all_key", "get_all_format_date : locale = " . $locale;
}

get_all_format_time: {
    my @keys = Socialtext::Date::l10n->get_all_format_time($locale);
    my @sorted_keys = sort @keys;
    is "@sorted_keys", "@time_all_key", "get_all_format_time : locale = " . $locale;
}

}

