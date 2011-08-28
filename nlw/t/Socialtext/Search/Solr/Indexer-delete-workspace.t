#!perl
# @COPYRIGHT@
use strict;
use warnings;

BEGIN {
    $ENV{NLW_APPCONFIG} = 'search_factory_class=Socialtext::Search::Solr::Factory';
}

use Test::Socialtext;
use Test::Socialtext::Search;

plan tests => 1;
ok "Test removed until we decide to implement Solr WS Search";
exit;

fixtures(qw( db no-ceq-jobs ));

plan skip_all => 'Solr page & attachment indexing is turned off';

plan tests => 19;

my $hub = create_test_hub();
Test::Socialtext->main_hub($hub);

# make an index and confirm it works
index_exists();

# remove the index
index_removed();

# makes sure things still work when we try again
index_exists();
exit;

sub index_exists {
    create_and_confirm_page(
        'a test page',
        "a simple page containing a funkity string"
    );
    search_for_term('funkity');
}

sub index_removed {
    Socialtext::Search::Solr::Factory->create_indexer(
        $hub->current_workspace->name )->delete_workspace();

    search_for_term('funkity', 1);
}
