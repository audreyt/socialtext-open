#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 3;
fixtures(qw( empty ));

BEGIN {
    use_ok( "Socialtext::Search::Solr::Factory" );
}

my $indexer = Socialtext::Search::Solr::Factory->create_indexer( 'empty' );
isa_ok( $indexer, 'Socialtext::Search::Solr::Indexer', "I HAS A FLAVOR!" );

my $searcher = Socialtext::Search::Solr::Factory->create_searcher( 'empty' );
isa_ok( $searcher, 'Socialtext::Search::Solr::Searcher', "I TOO HAS A FLAVOR!" );
