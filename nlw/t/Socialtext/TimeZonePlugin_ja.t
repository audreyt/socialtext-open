#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Scalar::Defer;
use mocked 'Socialtext::l10n' => qw( loc loc_lang ); loc(); loc_lang('ja');
use utf8;
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

use Test::More;
use Test::Socialtext;
fixtures(qw( empty ));

BEGIN {
    unless ( eval { require DateTime::Format::HTTP; 1 } ) {
        plan skip_all => 'These tests require DateTime::Format::HTTP to run.';
    }
}

use DateTime;
use Socialtext::TimeZonePlugin;

my $zones = Socialtext::TimeZonePlugin->zones;
my $hub = new_hub('empty');
my $prefs = $hub->preferences_object;

my $tz = $hub->timezone;

my @formats = qw( yyyy_mm_dd yyyy_mm_dd_sl yyyy_mm_dd_jp );
my %strftime_formats = ( 'yyyy_mm_dd' => '%Y-%m-%d',
                         'yyyy_mm_dd_sl' => '%Y/%m/%d',
                         'yyyy_mm_dd_jp' => '%Y年%m月%d日',
                       );

my @dst = qw( on off auto-us never );
my @hours_display = qw( 24 12ampm 24_ja );

my %strftime_time_formats = ( '24' => '%H:%M',
                              '12ampm' => '%p %I:%M',
                              '24_ja' => '%H時%M分',
                            );

my %strftime_time_sec_formats = ( '24' => '%H:%M:%S',
                              '12ampm' => '%p %I:%M:%S',
                              '24_ja' => '%H時%M分%S秒',
                             );

my @show_seconds  = ( 0, 1 );

my @tests = 
    ( { string => '2004-10-15 09:30:05',
        is_dst => 1,
      },
      { string => '2004-12-06 15:30:31',
        is_dst => 0,
      },
    );

$_->{dt} = DateTime::Format::HTTP->parse_datetime( $_->{string}, 'UTC' ) for @tests;

my $permutations = 
  (keys %$zones) * @formats * @dst * @hours_display * @show_seconds;
my %test_numbers = ();
if ($ENV{NLW_TEST_FASTER}) 
{
    my $total_tests = 10;
    $test_numbers{int(rand($permutations))} = 1
      while scalar(keys %test_numbers) < $total_tests;
    $permutations = $total_tests;
}

my $formats_re = join '|', @formats;

# Is there a less grotesque way to do this?
# I don't know, but there is a _FASTER way.
my $i = 0;
foreach my $z ( keys %$zones ) {
    foreach my $f (@formats) {
        foreach my $dst (@dst) {
            foreach my $h (@hours_display) {
                foreach my $s (@show_seconds) {
                    if (not($ENV{NLW_TEST_FASTER}) or
                        exists($test_numbers{$i++}))
                    {
                        $prefs->timezone->value($z);
                        $prefs->date_display_format->value($f);
                        $prefs->dst->value($dst);
                        $prefs->time_display_12_24->value($h);
                        $prefs->time_display_seconds->value($s);
                        run_tests($prefs);
                    }
                }
            }
        }
    }
}

# These tests make sure that when the year is equal to this
# year, it is not included with the short date formats.
{
    my $date_with_this_year = 1900 + (localtime)[5] . '-12-05 10:10:10';
    $prefs->timezone->value('+0000');
    $prefs->dst->value('off');
    $prefs->time_display_12_24->value('24');
    $prefs->time_display_seconds->value(0);

    my %fmts = (
        yyyy_mm_dd    => '2011-12-05 10:10',
        yyyy_mm_dd_sl => '2011/12/05 10:10',
        yyyy_mm_dd_jp => '2011年12月05日 10:10',
    );

    for my $fmt (keys %fmts) {
        $prefs->date_display_format->value($fmt);
        is( $tz->date_local( $date_with_this_year ), $fmts{$fmt},
            "test short date format with current year - $fmt" );
    }
}

done_testing;
exit;

sub run_tests
{
    my $prefs = shift;

    my $tz_pref = $prefs->timezone->value;
    my $dst_pref = $prefs->dst->value;
    my $time_display_pref = $prefs->time_display_12_24->value;
    my $seconds_pref = $prefs->time_display_seconds->value;

    foreach my $test (@tests)
    {
        my $dt = $test->{dt}->clone;
        my $zone = $tz_pref;
        $zone =~ s/(?:nz|id)$//;
        $dt->set_time_zone($zone);

        if ( $dst_pref eq 'on' ||
             ( $dst_pref eq 'auto-us' && $test->{is_dst} )
           )
        {
            $dt->add( minutes => 60 );
        }

        my $strftime = $strftime_formats{ $prefs->date_display_format->value };

        $strftime .= ' ';
        if ( $seconds_pref ) {
            $strftime .= $strftime_time_sec_formats{ $prefs->time_display_12_24->value };
        }else{
            $strftime .= $strftime_time_formats{ $prefs->time_display_12_24->value };
        }

        my $sturfed = $dt->strftime($strftime);
        $sturfed =~ s/AM/午前/;
        $sturfed =~ s/PM/午後/;
        is( $tz->date_local( $test->{string} ), $sturfed,
            "Formatting of $test->{string} (strftime = $strftime, dst = $dst_pref, zone = $tz_pref, 12/24 = $time_display_pref)" );
    }
}
