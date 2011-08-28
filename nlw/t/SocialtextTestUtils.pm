package t::SocialtextTestUtils;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw/index_page/;

# Index a particular page, usually for search related tests
sub index_page {
    my $wksp = shift;
    my $page = shift;

    local $ENV{NLW_APPCONFIG} = 'ceqlotron_synchronous=1';
    require Socialtext::Search::AbstractFactory;
    my $indexer
        = Socialtext::Search::AbstractFactory->GetFactory->create_indexer(
        $wksp,
        config_type => 'live',
    );
    if ( !$indexer ) {
        die "Couldn't create an indexer\n";
    }
    $indexer->index_page( $page );
}


1;
