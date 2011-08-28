#!perl
# @COPYRIGHT@

use warnings;
use strict;
use utf8;

use Test::HTTP::Socialtext '-syntax', tests => 14;

use Readonly;
use Test::Live fixtures => ['admin'];

our $TODO;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $PAGE_NAME => 'Euripides';
Readonly my $PAGE_BODY => 'xyzzy';

test_http "GET nonexistent $PAGE_NAME" {
    >> GET $BASE/$PAGE_NAME

    << 404
}

test_http "Parameter-tunneled PUT of $PAGE_NAME" {
    >> POST $BASE/$PAGE_NAME?http_method=PUT
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $PAGE_BODY

    << 201
}

test_http "GET new $PAGE_NAME" {
    >> GET $BASE/$PAGE_NAME
    >> Accept: text/x.socialtext-wiki

    << 200
    <<
    << $PAGE_BODY
    << 
}

test_http "GET nonexistent $PAGE_NAME 2" {
    >> GET $BASE/$PAGE_NAME 2

    << 404
}

# XXX: I don't understand why I need the extra trailing newline here to get
# this test to pass.
test_http "Header-tunneled PUT of $PAGE_NAME 2" {
    >> POST $BASE/$PAGE_NAME 2
    >> X-HTTP-Method: PUT
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $PAGE_BODY

    << 201
}

# XXX: I don't understand why I need the extra trailing newline here to get
# this test to pass.
test_http "GET new $PAGE_NAME 2" {
    >> GET $BASE/$PAGE_NAME 2
    >> Accept: text/x.socialtext-wiki

    << 200
    <<
    << $PAGE_BODY
    << 
}

test_http "GET JSON when HTML accept" {
    >> GET $BASE/$PAGE_NAME 2?accept=application/json
    >> Accept: text/html

    << 200
    << Content-type: application/json; charset=UTF-8
}

test_http "Tunneling over GET does nothing." {
    >> GET $BASE/$PAGE_NAME 2?http_method=DELETE

    << 200

    >> GET $BASE/$PAGE_NAME 2

    << 200
}

test_http "Parameter-tunneled DELETE of $PAGE_NAME 2" {
    >> POST $BASE/$PAGE_NAME 2?http_method=DELETE

    << 204

    >> GET $BASE/$PAGE_NAME 2

    << 404
}

