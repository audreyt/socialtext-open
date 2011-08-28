#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 34;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin_with_extra_pages', 'foobar'];
use Test::More;

Readonly my $BASE => Test::HTTP::Socialtext->url;
Readonly my $URI  => "$BASE/data/workspaces/admin/pages/Admin wiki/tags";
Readonly my $URI2 => "$BASE/data/workspaces/admin/pages/start here/tags";
Readonly my $URI3 => "$BASE/data/workspaces/admin/pages/babel/tags";

test_http "GET no tags json" {
    >> GET $URI
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $representation = decode_json( $test->response->content );
    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is_deeply( $representation, [], 'No tags.' );
}

test_http "GET no tags text" {
    >> GET $URI
    >> Accept: text/plain

    << 200

    my $content = $test->response->content();
    chomp($content);

    is $content, '', 'no tags present';

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
    is( scalar @$representation, 1, 'Now have 1 tag.' );
    ok( exists $representation->[0]->{uri}, 'Tag has a URI.' );
    is( $representation->[0]->{name}, 'foo', '"foo" tag has been added.' );
}

test_http "GET tags in HTML by default" {
    >> GET $URI

    << 200
    ~< Content-type: \btext/html\b
    <<
    ~< (?xs)<title> \s* Tags \s+ for \s+ page \s+ Admin\ wiki \s* </title>
    ~< (?xs)<h1> \s* Tags \s+ for \s+ page \s+ Admin\ wiki \s* </h1>
    ~< foo
}

test_http "GET tags in plaintext" {
    >> GET $URI
    >> Accept: text/plain

    << 200
    ~< Content-type: \btext/plain\b
    <<
    << foo
    << 
}

test_http "POST up some tags to generate weight" {
    >> POST $URI
    >> Content-type: text/plain
    >>
    >> bar

    << 201

    >> POST $URI
    >> Content-type: text/plain
    >>
    >> baz

    << 201

    >> POST $URI2
    >> Content-type: text/plain
    >>
    >> foo

    << 201

    >> POST $URI3
    >> Content-type: text/plain
    >>
    >> foo

    << 201
}

test_http "GET tags weighted order" {
    >> GET $URI?order=weighted
    >> Accept: application/json

    << 200
    ~< Content-type: application/json

    my $content = $test->response->content;
    my $representation = decode_json( $content );

    isa_ok( $representation, 'ARRAY', 'Tags representation' );
    is( scalar @$representation, 3, 'Now have 3 tags.' );
    ok( exists $representation->[0]->{uri}, 'Tag has a URI.' );
    is( $representation->[0]->{name}, 'foo', '"foo" tag is present.' );
    is( $representation->[0]->{page_count}, '3', '"foo" tag is present on 3 pages.' );

}

{
    no warnings 'once';
    $Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
    test_http "POST new tag as non-member user and fail" {
        >> POST $URI
        >> Content-type: text/plain
        >>
        >> foo

        << 403
    }
}
