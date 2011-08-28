#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 7;
fixtures( 'admin' );
use XML::Feed;

my $hub = new_hub('admin');
my $xml  = $hub->syndicate->_syndicate_page_named( 'Atom', 'Quick Start' )->as_xml;
my $feed = XML::Feed->parse( \$xml );
my $page = $hub->pages->new_from_name('Quick Start');

my $title   = $feed->title;
my $format  = $feed->format;
my $link    = $feed->link;
my @entries = $feed->entries;

like( $title, qr/Quick Start/, 'feed title should contain page title' );
is( $format,         'Atom',          'feed format should be Atom' );
is( $link,           $page->full_uri, 'feed link should be page uri' );
is( scalar @entries, 1,               'feed should contain only one entry' );
like(
    $entries[0]->content->body, qr/Then type as you like/,
    'feed contains '
);
is( $entries[0]->link,  $page->full_uri, 'entry link should be page uri' );
is( $entries[0]->title, $page->title,    'entry title should be page title' );

