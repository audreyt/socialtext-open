#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 18;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin_no_pages'];
use Test::More;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $PAGE_ONE => 'page one';
Readonly my $PAGE_TWO => 'page two';

Readonly my $NEW_BODY      => "You got to drop her like a trig class.\n";

test_http "PUT new page one" {
    my $body = $NEW_BODY . "\n\n[page two]";

    >> PUT $BASE/$PAGE_ONE
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $body

    << 201

}

# test for an incipient frontlink on the page we just PUT
test_http "GET frontlinks of page one" {
    >> GET $BASE/$PAGE_ONE/frontlinks?incipient=1
    >> Accept: text/html

    << 200

    my $content = $test->response->content;
    like $content, qr{page_two}, 'page one has page_two as an incipient frontlink';
}

test_http "PUT new page two" {
    my $body = $NEW_BODY . "\n\n[page one]";

    >> PUT $BASE/$PAGE_TWO
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $body

    << 201
}

test_http "get incipient frontlinks of page one, none" {
    >> GET $BASE/$PAGE_ONE/frontlinks?incipient=1
    >> Accept: application/json

    << 200

    my $result = decode_json($test->response->content);

    is ref($result), 'ARRAY', 'result is an array';
    is scalar @$result, 0, '0 items in the array';
}

test_http "GET page one frontlinks" {
    >> GET $BASE/$PAGE_ONE/frontlinks
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;

    like $content, qr{page two}, 'page one has page two as a frontlink';
}

test_http "DELETE page two, check frontlinks empty" {
    >> DELETE $BASE/$PAGE_TWO

    << 204

    >> GET $BASE/$PAGE_ONE/frontlinks
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;
    chomp($content);

    is $content, '', 'no frontlinks for page one after deleting page two';

    >> GET $BASE/$PAGE_ONE/frontlinks
    >> Accept: text/html

    << 200

    >> GET $BASE/$PAGE_ONE/frontlinks
    >> Accept: application/json

    << 200

    my $result = decode_json($test->response->content);

    is ref($result), 'ARRAY', 'result is an array';
    is scalar @$result, 0, '0 items in the array';
}

test_http "page rontlinks incipient include page two" {
    >> GET $BASE/$PAGE_ONE/frontlinks?incipient=1
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;

    like $content, qr{page two}, 'page one has page two as an incipient frontlink';
}

