#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 8;

use Readonly;
use Test::Live fixtures => ['admin', 'foobar'];

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $PAGE_NAME => 'Admin wiki';
Readonly my $COMMENT   => 'Do you use them for good, or for awesome?';

# REVIEW: Below, I'm justing expect '204 No Content' for now, because I'm not
# sure what the POST of a new comment should return.  Since a new comment was
# created, it could be argued that '201 Created' is correct.  But where does
# Location point?  The URL of the page is all we've got, but that seems wrong.
test_http "Add comment" {
    >> GET $BASE/$PAGE_NAME
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< Content-type: \btext/x\.socialtext-wiki\b

    my $original_body = $test->response->content;

    >> POST $BASE/$PAGE_NAME/comments
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $COMMENT

    << 204

    >> GET $BASE/$PAGE_NAME
    >> Accept: text/x.socialtext-wiki


    << 200
    ~< Content-type: \btext/x\.socialtext-wiki\b
    <<
    ~< (?sxm) \A \Q$original_body\E .* \Q$COMMENT\E
}

test_http "Bad type" {
    >> POST $BASE/$PAGE_NAME/comments
    >> Content-type: application/vnd.ms-excel
    >>
    >> $COMMENT

    << 415
}

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "non-member user no comment" {
    >> POST $BASE/$PAGE_NAME/comments
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $COMMENT

    << 403
}
