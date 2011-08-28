#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 8;
fixtures(qw( clean empty ));

BEGIN {
    use_ok( "Socialtext::WeblogArchive" );
    use_ok( "Socialtext::Page" );
}

my @years = qw(2006 2005 2004 2003);
my %months = (
    January  => 1,
    March    => 3,
    May      => 5,
    October  => 10,
    December => 12,
);

my $hub = new_hub('empty');

create_pages();
test_archive();
test_html();

sub test_archive {
    my $archive = $hub->weblog_archive->assemble_archive('archive blog');

    my @results;
    foreach my $year (sort {$b <=> $a} keys %$archive) {
        foreach my $month (sort {$b <=> $a} keys %{$archive->{$year}}) {
            push @results, "$year:$month";
        }
    }

    is( $results[0], '2006:12', 'correct year and month on first entry' );
    is( $results[1], '2006:10', 'correct year and month on second entry' );
    is( $results[-2], '2003:3',
        'correct year and month on penultimate entry' );
    is( $results[-1], '2003:1', 'correct year and month on last entry' );
}

sub test_html {

    my $html = $hub->weblog_archive->weblog_archive_html('archive blog');

    my @lines = split(/\n{2,}/, $html);
    like( $lines[0], qr{December 2006}, 'first line is december 2006' );
    like( $lines[-1], qr{January 2003}, 'last line is january 2004' );
}

sub create_pages {
    foreach my $year (@years) {
        foreach my $month (keys(%months)) {
            create_page($year, $month);
        }
    }
}

sub create_page {
    my $year  = shift;
    my $month = shift;
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title      => "Happy $year $month",
        content    => "this is our $year and $month",
        categories => ['archive blog'],
        date       => DateTime->new(
            year  => $year,
            month => $months{$month},
            day   => 2,
        ),
        creator    => $hub->current_user,
    );
}
