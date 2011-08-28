#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 5;
fixtures( 'admin', 'foobar' );

my $admin  = new_hub('admin');

my $content1 = "\n{link foobar [Quick Start]}\n";
my $content2 = "\n{link foobar [Wiki 666]}\n";

{
    my $viewer = $admin->viewer;
    isa_ok( $viewer, 'Socialtext::Formatter::Viewer' );

    my $output1 = $viewer->text_to_html($content1);
    my $output2 = $viewer->text_to_html($content2);

    ok( $output1, 'output 1 exists');
    ok( $output2, 'output 2 exists');
    like( $output1, qr/quick_start/, 'output 1 is uri' );
    like( $output2, qr/Wiki%20666/, 'output 2 is name' );
}
