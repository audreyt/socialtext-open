#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 4;
fixtures( 'admin' );

use Socialtext::Search::AbstractFactory;

Socialtext::Search::AbstractFactory->GetFactory->create_indexer('admin')
    ->index_page('quick_start');

my $hub = new_hub('admin');

run {
    my $case = shift;
    my $query = $case->query;

    $hub->search->search_for_term(search_term => $query);
    my $set = $hub->search->result_set;
    my $message = $hub->search->error_message || '';

    chomp(my $match = $case->message);
    if ($match) {
        like($message, qr/$match/, $case->name . " got expected error message");
    }

    my $hits = $set->{hits};
    if ($case->expected_results) {
        ok($hits >= $case->expected_results, $case->name . " we have results");
    } else {
        ok($hits == 0, $case->name . " we have no results");
    }

    $hub->search->error_message(undef);
}


__DATA__
=== correct title field
--- query: title:quick
--- expected_results: 1
--- message

=== quoted title field
--- query: title:"quick start"
--- expected_results: 1
--- message

=== correct category field
--- query: category:welcome
--- expected_results: 1
--- message

=== correct category field no results
--- query: category:funk
--- expected_results: 0
--- message
