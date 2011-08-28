#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 13;

use Readonly;
use Socialtext::JSON;
use Socialtext::Rest::Version;
use Test::More;
use Test::Live fixtures => ['admin'];

Readonly my $URL => Test::HTTP::Socialtext->url('/data/version');

test_http "default is text/plain" {
    >> GET $URL

    << 200
    ~< Content-type: \btext/plain\b
    <<
    << $Socialtext::Rest::Version::API_VERSION
}

test_http "text/plain" {
    >> GET $URL
    >> Accept: text/plain

    << 200
    ~< Content-type: \btext/plain\b
    <<
    << $Socialtext::Rest::Version::API_VERSION
}

test_http "application/json" {
    >> GET $URL
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $representation = decode_json( $test->response->content );
    isa_ok( $representation, 'ARRAY', "JSON representation looks correct." );
    is( $#$representation, 0, "JSON representation has only one element." );
    is( $representation->[0], $Socialtext::Rest::Version::API_VERSION,
        "JSON version # is correct" );
}

for my $method qw(PUT DELETE) {
    test_http "$method is a bad method" {
        >> $method $URL

        << 405
    }
}
