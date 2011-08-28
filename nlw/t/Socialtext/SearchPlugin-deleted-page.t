#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 11;
use Test::Socialtext::Search;

fixtures(qw( db no-ceq-jobs ));

my $hub = create_test_hub();
Test::Socialtext->main_hub( $hub );

{
    my $title = 'A Page with a Wacktastic Title';
    create_and_confirm_page(
        $title,
        'totally irrelevant'
    );
    search_for_term('wacktastic');

    delete_page($title);

    search_for_term( 'wacktastic', 'should not be found' );
}
