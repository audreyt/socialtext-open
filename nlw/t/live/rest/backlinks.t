#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::HTTP::Socialtext '-syntax', tests => 11;
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

test_http "PUT new page two" {
    my $body = $NEW_BODY . "\n\n[page one]";

    >> PUT $BASE/$PAGE_TWO
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $body

    << 201
}

test_http "GET page one backlinks" {
    >> GET $BASE/$PAGE_ONE/backlinks
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;

    like $content, qr{page two}, 'page one has page two as a backlink';
}

test_http "DELETE page two, check backlinks 404" {
    >> DELETE $BASE/$PAGE_TWO

    << 204

    >> GET $BASE/$PAGE_ONE/backlinks
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;
    chomp($content);

    is $content, '', 'no backlinks for page one after deleting page two';

    >> GET $BASE/$PAGE_ONE/backlinks
    >> Accept: text/html

    << 200

    >> GET $BASE/$PAGE_ONE/backlinks
    >> Accept: application/json

    << 200

    my $result = decode_json($test->response->content);

    is ref($result), 'ARRAY', 'result is an array';
    is scalar @$result, 0, '0 items in the array';
}


