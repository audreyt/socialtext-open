#!/usr/bin/env perl
# @COPYRIGHT@

# run this as perl -d:DProf bench/recent-changes.pl <count> to profile 
# generating new recent changes over and over

use strict;
use warnings;

use lib 'lib';
use Test::Socialtext;
use Data::Dumper;

my $hub = new_hub('admin');
my $rc = $hub->recent_changes;

my $count = $ARGV[0];
$count || 1;
$| = 1;

for my $counter (1 .. $count) 
{
    $rc->new_changes;
    print '.';
    warn Dumper($rc->result_set) if $ARGV[1];
}
print "\n";

