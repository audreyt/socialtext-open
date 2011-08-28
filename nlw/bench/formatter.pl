#!/usr/bin/env perl
# @COPYRIGHT@

# run this as perl -d:DProf bench/formatter.pl <count> to profile multiple 
# formattings of a complex page

use strict;
use warnings;

use lib 'lib';
use Test::Socialtext;

my $hub = new_hub('admin');
my $pages = $hub->pages;
my @all_pages = grep $_->active, $pages->all;

my $count = $ARGV[0];
$count || 1;
$| = 1;

my @bleed_pages = ();
for my $counter (1 .. $count) 
{

    if ($counter == 1 or not @bleed_pages) {
        @bleed_pages = @all_pages;
    }
    my $page = random_page(\@bleed_pages);
    my $output = $page->to_html;
    print '.';
    print '####### ', $page->title, "\n", $output if $ARGV[1];
}
print "\n";

sub random_page {
    my $pages_ref = shift;

    my $index = int( rand(@$pages_ref) );
    my $page = $pages_ref->[$index];
    splice @$pages_ref, $index, 1;
    return $page;
}
