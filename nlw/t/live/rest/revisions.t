#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 18;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin_no_pages'];
use Test::More;

Readonly my $TYPE => 'text/x.socialtext-wiki';
Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages/test_page');

Readonly my $YEAR => 1900 + (localtime)[5];

my $Revision_id;

# make a few changes to a page to create some revisions
test_http "PUT page content" {
    >> PUT $BASE
    >> Content-type: $TYPE
    >>
    >> Hello one

    << 201

    sleep 1;

    >> PUT $BASE
    >> Content-type: $TYPE
    >>
    >> Hello two

    << 204

    sleep 1;

    >> PUT $BASE
    >> Content-type: $TYPE
    >>
    >> Hello three

    << 204

}

test_http "GET revisions text/plain" {
    >> GET $BASE/revisions
    >> Accept: text/plain

    << 200
    <<
    ~< ^test_page:$YEAR

}

test_http "GET revisions text/html" {
    >> GET $BASE/revisions
    >> Accept: text/html

    << 200
    <<
    ~< test_page version $YEAR

}

test_http "GET revisions application/json" {
    >> GET $BASE/revisions
    >> Accept: application/json

    << 200

    my $result = decode_json($test->response->content);

    is ref $result, 'ARRAY', 'revisions request returns list';
    is scalar @$result, 3, '3 revisions are returned';
    foreach my $revision (@$result) {
        is $revision->{name}, 'test_page', 'revision is right page';
    }
    $Revision_id = $result->[0]->{revision_id};
}

# retrieve a revision
test_http "GET first revision" {
    >> GET $BASE/revisions/$Revision_id
    >> Accept: text/x.socialtext-wiki

    << 200
    <<
    ~< Hello one
}

test_http "GET first revision as JSON" {
    >> GET $BASE/revisions/$Revision_id
    >> Accept: application/json

    << 200

    my $result = decode_json($test->response->content);

    is $result->{revision_id}, $Revision_id,
        "Revision id of first revision is $Revision_id";

}

# retrieve a bad revision
test_http "GET bad revision" {
    >> GET $BASE/revisions/alphabunny5
    >> Accept: text/x.socialtext-wiki

    << 404
}

