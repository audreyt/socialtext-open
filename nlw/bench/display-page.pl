# @COPYRIGHT@
use Test::Socialtext;

use strict;

use lib 'lib';
use Test::Socialtext::Environment;


my $hub = new_hub('admin');
my $display = $hub->display;
my $pages = $hub->pages;

my $count = $ARGV[0];
$count || 1;
$| = 1;

for (1 .. $count) 
{
    $pages->current( $pages->new_from_name('help') );

    my $output = $display->display;
    print '.';
    print $output if $ARGV[1];
}
print "\n";
