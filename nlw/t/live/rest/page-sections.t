#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 11;

use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin_no_pages'];
use Test::More;

Readonly my $BASE      => Test::HTTP::Socialtext->url;
Readonly my $PAGES_URI => "$BASE/data/workspaces/admin/pages";
Readonly my $SINGAPORE => join '', map { chr($_) } 26032, 21152, 22369;
Readonly my $PAGE_NAME => "Sections Test";
Readonly my $CONTENT   => <<"EOF";

^ Header one

para one

^^ Header two

{section $SINGAPORE} para two

^ Header three

para three

^^^^^ Header four

* list one

EOF

test_http "PUT a new page" {
    >> PUT $PAGES_URI/$PAGE_NAME
    >> Content-Type: text/x.socialtext-wiki
    >>
    >> $CONTENT

    << 201
}

test_http "GET page sections" {
    >> GET $PAGES_URI/$PAGE_NAME/sections
    >> Accept: text/plain

    << 200
    ~< Content-type: \btext/plain\b

    my @sections = split( "\n", $test->response->decoded_content );
    is scalar @sections, 5, 'there are five sections on the page';
    is_deeply [@sections],
        [
        'Header one', 'Header two', $SINGAPORE, 'Header three',
        'Header four'
        ],
        'the sections are correct and ordered correctly';
}

test_http "GET page sections JSON" {
    >> GET $PAGES_URI/$PAGE_NAME/sections
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $representation = decode_json( $test->response->decoded_content );
    isa_ok $representation, 'ARRAY', 'Sections representation is an array';
    is scalar @$representation, 5, 'there are five items in the json list';

    is $representation->[0]->{name}, 'Header one',
        'first header name is correct';
    is $representation->[0]->{uri}, '../sections_test#header_one',
        'first header section uri is correct';
}
