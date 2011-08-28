#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 13;

use Test::Live fixtures => ['admin', 'foobar']; # use foobar to get devnull2
use Readonly;
use Test::More;

Readonly my $LIVE => Test::Live->new();
Readonly my $BASE => Test::HTTP::Socialtext->url('/data/workspaces/admin');
Readonly my $TAG_EXIST    => 'tag exist';
Readonly my $TAG_NO_EXIST => 'tag no exist';

test_http "PUT new tag in workspace" {
    >> PUT $BASE/tags/$TAG_EXIST

    << 201
}

test_http "PUT tag on a page" {
    >> PUT $BASE/pages/Admin Wiki/tags/$TAG_EXIST

    << 201
}

test_http "GET existing tag in workspace" {
    >> GET $BASE/tags/$TAG_EXIST

    << 200

}

test_http "GET non-existing tag" {
    >> GET $BASE/tags/$TAG_NO_EXIST

    << 404
}

test_http "DELETE non-existing tag" {
    >> DELETE $BASE/tags/$TAG_NO_EXIST

    << 404
}

test_http "DELETE then GET existing tag" {
    >> DELETE $BASE/tags/$TAG_EXIST

    << 204

    >> GET $BASE/tags/$TAG_EXIST

    << 404

    >> GET $BASE/pages/admin/Admin Wiki/tags/$TAG_EXIST

    << 404
}

test_http "POST fails to 405" {
    >> POST $BASE/tags/$TAG_EXIST

    << 405
    ~< Allow: ^GET, HEAD, PUT, DELETE
}

test_http "PUT new tag back in workspace" {
    >> PUT $BASE/tags/$TAG_EXIST

    << 201
}

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "GET tag as unauthed user" {
    >> GET $BASE/tags/$TAG_EXIST

    << 403
}

test_http "DELETE tag as unauthed user" {
    >> DELETE $BASE/tags/$TAG_EXIST

    << 403
}

