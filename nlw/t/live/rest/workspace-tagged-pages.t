#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 5;

use Readonly;
use Test::Live fixtures => ['admin'];
use Test::More;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/tags/welcome/pages');

test_http "DELETE pages is a bad method" {
    >> DELETE $BASE

    << 405
    ~< Allow: ^GET
}

test_http "GET lists the pages" {
    >> GET $BASE
    >> Accept: text/plain

    << 200
    
    my $body  = $test->response->content();

    like $body, qr{Quick Start}, 'Quick Start page is in results';
    like $body, qr{Meeting agendas}, 'Meeting agendas page is in results';
}

