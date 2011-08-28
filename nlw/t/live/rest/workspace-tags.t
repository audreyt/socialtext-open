#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 40;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin'];
use Test::More;

Readonly my $URI =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/tags');

test_http "GET no tags" {
    >> GET $URI
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $representation = decode_json( $test->response->content );
    isa_ok( $representation, 'ARRAY', 'Tags representation' );

    # somewhere is the welcome tag
}

test_http "POST then GET new tag" {
    >> POST $URI
    >> Content-type: text/plain
    >>
    >> foo

    << 201
    ~< Location: foo

    >> GET $URI
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $representation = decode_json( $test->response->content );
    isa_ok( $representation, 'ARRAY', 'Tags representation' );

    # somewhere is the foo tag
}

test_http "GET tags in HTML by default" {
    >> GET $URI

    << 200
    ~< Content-type: \btext/html\b
    <<
    ~< (?xs)<title> \s* Tags \s+ for \s+ Admin\ Wiki \s* </title>
    ~< (?xs)<h1> \s* Tags \s+ for \s+ Admin\ Wiki \s* </h1>
    ~< foo
}

test_http "GET tags in plaintext" {
    >> GET $URI
    >> Accept: text/plain

    << 200
    ~< Content-type: \btext/plain\b
    <<
    << foo
    << welcome
    << 
}

test_http "PUT get a bad method" {
    >> PUT $URI
    >> Content-type: text/plain

    << 405
}

test_http "GET tags weighted order" {
    >> GET $URI?order=weighted
    >> Accept: application/json

    << 200
    ~< Content-type: application/json

    my $representation = decode_json( $test->response->content );

    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is( scalar @$representation, 2, 'Now have 2 tags.' );
    ok( exists $representation->[1]->{uri}, 'Tag has a URI.' );
    is( $representation->[0]->{name}, 'welcome', '"welcome" tag is present.' );
    is( $representation->[1]->{name}, 'foo', '"foo" tag is present.' );
    is( $representation->[1]->{page_count}, '0', '"foo" tag is present on 0 pages.' );

}

foreach my $tag qw(alpha1 alpha2 alpha3 beta1 beta2 beta3) {
    test_http "make tag $tag" {
        >> POST $URI
        >> Content-type: text/plain
        >>
        >> $tag

        << 201

    }
}

# REVIEW: unclear how escaping and such will/should work out here? TEST IT!
test_http "GET tags regexp" {
    >> GET $URI?filter=^a
    >> Accept: application/json

    << 200

    my $representation = decode_json( $test->response->content );

    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is( scalar @$representation, 3, 'Filter on ^a gets 3 tags.' );

    >> GET $URI?filter=3
    >> Accept: application/json

    << 200

    $representation = decode_json( $test->response->content );

    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is( scalar @$representation, 2, 'Filter on 3 gets 2 tags.' );

    >> GET $URI?filter=holiness
    >> Accept: application/json

    << 200

    $representation = decode_json( $test->response->content );

    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is( scalar @$representation, 0, 'Filter on holiness gets 0 tags.' );

}
