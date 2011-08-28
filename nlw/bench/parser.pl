#!perl
# @COPYRIGHT@

# run this as perl -d:DProf bench/parser.pl <count> to profile 
# parsing a page over and over

use strict;
use warnings;

use lib 'lib';
use Test::Socialtext;

my $hub = new_hub('admin');
my $parser = Socialtext::Formatter::Parser->new(
    table => $hub->formatter->table,
    wafl_table => $hub->formatter->wafl_table,
);
my $page = $hub->pages->new_from_name('FormattingTest');
my $text = $page->content;

my $count = $ARGV[0];
$count || 1;
$| = 1;

for my $counter (1 .. $count) 
{
    $parser->text_to_parsed($text);
    print '.';
}
print "\n";

