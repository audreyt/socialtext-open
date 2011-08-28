#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 7;
fixtures(qw( empty ));

my $hub   = new_hub('empty');
my $pages = $hub->pages;

my $x255 = 'x' x 255;
my $x256 = 'x' x 256;
my $encode_to_255 = ('x' x 127) . ' ' . ('x' x 127);
my $encode_to_256 = ('x' x 127) . "\x{203F}" . ('x' x 127);

{
    my $page = $pages->new_from_name($x255);
    isa_ok( $page, 'Socialtext::Page', 'A page with a 255 character id is allowed' );
}

{
    my $page = $pages->new_from_name($x256);
    ok( ! $page, 'A page with a 256 character id is not allowed' );
}

{
    my $page = $pages->new_from_name($encode_to_255);
    isa_ok( $page, 'Socialtext::Page', 'A page with a 255 character id after encoding is allowed' );
}

{
    my $page = $pages->new_from_name($encode_to_256);
    ok( ! $page, 'A page with a 256 character id after encoding is not allowed' );
}

my $viewer = $hub->viewer;
isa_ok( $viewer, 'Socialtext::Formatter::Viewer' );

{
    my $result = $viewer->text_to_html( "[$x255]\n" );
    like( $result, qr/href/, 'viewer generates link for valid page id' );
}

{
    my $result = $viewer->text_to_html( "[$x256]\n" );
    unlike( $result, qr/href/, 'viewer does not generates link for invalid page id' );
}
