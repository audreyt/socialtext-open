#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::More tests => 4;
use Readonly;

Readonly my $PAGE_URI     => 'a_page';
Readonly my $PAGE_HIT => {
    excerpt => '... blah blah blah ...',
    key     => 'somethin'
};

Readonly my $WS_NAME      => 'socialtext';
Readonly my $NEW_PAGE_URI => 'another_page';

BEGIN {
    use_ok( "Socialtext::Search::SimplePageHit" );
}

# This test could be moved to t/Socialtext/PageHit.t and used to test multiple
# PageHit implementations when we have them.

my $page_hit = Socialtext::Search::SimplePageHit->new( $PAGE_HIT, $WS_NAME,
    $PAGE_URI );

ok( $page_hit->isa('Socialtext::Search::PageHit'), 'isa Socialtext::Search::PageHit' );

is( $page_hit->page_uri, $PAGE_URI, 'constructor picks up page URI' );

$page_hit->set_page_uri($NEW_PAGE_URI);

is( $page_hit->page_uri, $NEW_PAGE_URI, 'setter picks up page URI' );
