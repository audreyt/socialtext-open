#!perl
# @COPYRIGHT@

use warnings;
use strict;
use utf8;

use Test::HTTP::Socialtext '-syntax', tests => 18;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin', 'foobar']; # foobar for devnull2
use Test::More;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $EXISTING_NAME => 'Admin wiki';
Readonly my $TAG_EXIST     => 'tag exist';
Readonly my $TAG_NO_EXIST  => 'tag no exist';
Readonly my $UTF8_TAG      => 'Και';

test_http "PUT new tag" {
    >> PUT $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 201
}

test_http "GET existing tag" {
    >> GET $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 200
}

test_http "PUT new UTF8 tag" {
    >> PUT $BASE/$EXISTING_NAME/tags/$UTF8_TAG

    << 201
}

test_http "GET existing UTF8 tag" {
    >> GET $BASE/$EXISTING_NAME/tags/$UTF8_TAG

    << 200
}

test_http "GET non-existing tag" {
    >> GET $BASE/$EXISTING_NAME/tags/$TAG_NO_EXIST

    << 404
}

test_http "DELETE non-existing tag" {
    >> DELETE $BASE/$EXISTING_NAME/tags/$TAG_NO_EXIST

    << 404
}

test_http "DELETE then GET existing tag" {
    >> DELETE $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 204

    >> GET $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 404
}

test_http "POST fails to 405" {
    >> POST $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 405
    ~< Allow: ^GET, HEAD, PUT, DELETE
}

test_http "PUT tag exist back" {
    >> PUT $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 201
}

test_http "GET json rep" {
    >> GET $BASE/$EXISTING_NAME/tags/$TAG_EXIST
    >> Accept: application/json

    << 200
    ~< Content-type: application/json

    my $representation = decode_json( $test->response->content );

    isa_ok( $representation, 'HASH', 'Tags representation' );
    ok( exists $representation->{uri}, 'Tag has a URI.' );
    is( $representation->{name}, 'tag exist',
        '"tag exist" tag is present.' );
    is( $representation->{page_count}, '1',
        '"foo" tag is present on 1 page.' );
}

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "PUT tag as devnull2 and fail" {
    >> PUT $BASE/$EXISTING_NAME/tags/$TAG_EXIST

    << 403
}

