#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

=head1 SYNOPSIS

Using C<Statistics::Basic>, compute some statistics from a series of numbers presented on C<STDIN>.

    cat log | perl -pe '/overall:(\d+\.\d+)/; $_=$1' | stats.pl

Example output:

    | N | Mean | Median | Mode | Variance | StdDev           | Min | Max |
    | 5 | 12.4 | 6      | 1    | 270.24   | 16.4389780704276 | 1   | 45  |

Output should be a valid socialtext-wikitext table. It can be piped to
C<fix-tables> to make a nicely formatted table.

No effort is made to sanitize the input; garbage in, garbage out.


=cut

use List::Util qw(min max);
use Statistics::Basic;

my @stats = qw(Mean Median Mode Variance StdDev);
eval "require Statistics::Basic::$_" for @stats;

my @nums = <>;
chomp @nums;

my @results;

push @results, scalar(@nums);

foreach my $stat_name (@stats) {
    my $stat = "Statistics::Basic::$stat_name"->new(\@nums);
    push @results, $stat->query()
}

unshift @stats, 'N';

push @stats, 'Min', 'Max';
push @results, min(@nums);
push @results, max(@nums);

print "| ",join(" | ",@stats)," |\n";
print "| ",join(" | ",@results)," |\n";
