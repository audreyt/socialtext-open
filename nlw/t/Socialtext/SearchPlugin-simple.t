#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 7;
fixtures(qw( admin no-ceq-jobs ));

use Socialtext::Jobs;
use Socialtext::Search::AbstractFactory;

my $hub = new_hub('admin');
my $factory = Socialtext::Search::AbstractFactory->GetFactory;
warn $factory;
my $indexer = $factory->create_indexer('admin');
warn $indexer;
$indexer->index_page('quick_start');
ceqlotron_run_synchronously();

{
    $hub->search->search_for_term(search_term => 'page');

    my $set = $hub->search->result_set;
    ok( $set, 'we have results' );
    ok( $set->{hits} > 0, 'result set found hits' );
    is $set->{search_term}, 'page', "correct search_term";
    is $set->{scope}, '_', "correct scope";
    like( $set->{rows}->[0]->{Date}, qr/\d+/, 'date has some numbers in it');
    like( $set->{rows}->[0]->{DateLocal}, qr/\d+/,
        'date local has some numbers in it');
}
