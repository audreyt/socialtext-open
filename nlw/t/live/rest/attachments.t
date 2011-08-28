#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::HTTP::Socialtext '-syntax', tests => 45;
use Readonly;
use Socialtext::JSON;
use Socialtext::User;
use Test::Live fixtures => ['admin_with_extra_pages'];
use Test::More;

Readonly my $PAGE_BASE => Test::HTTP::Socialtext->url(
    '/data/workspaces/admin/pages/FormattingTest/attachments');
Readonly my $WORKSPACE_BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/attachments');

# add the devnull2
Socialtext::User->create(
        username        => 'devnull2@socialtext.com',
        email_address   => 'devnull2@socialtext.com',
        password        => 'd3vnu11l',
);

my %attachments = (
    'text/x.cowsay' => <<'END_OF_COW',
 ________________________________
< My stomachs do not like grain. >
 --------------------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
END_OF_COW
    'application/binary' =>
        "\x00\x01\x02\x03\x04This is binary, bitch!\x05\x06\x07\x08\x09",
);

test_http "DELETE attachments is a bad method" {
    >> DELETE $PAGE_BASE

    << 405
    << Allow: GET, HEAD, POST
}

test_http "GET HTML default" {
    >> GET $PAGE_BASE

    << 200
    ~< Content-type: \btext/html\b
    <<
    ~< test_image\.jpg
    ~< Robot\.txt
    ~< thing\.png
    ~< Rule #1
}

test_http "GET JSON" {
    >> GET $PAGE_BASE
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $response = decode_json( $test->response->content );

    isa_ok( $response, 'ARRAY', 'JSON response' );
    is( scalar @$response, 4, "JSON has 4 entries" );
}

test_http "GET text from Workspace" {
    >> GET $WORKSPACE_BASE
    >> Accept: text/plain

    << 200
    ~< Content-type: \btext/plain\b
    <<
    ~< Robot.txt

}

test_http "GET json from Workspace sorted alpha" {
    >> GET $WORKSPACE_BASE?order=alpha
    >> Accept: application/json

    << 200

    my $response = decode_json( $test->response->content );

    like $response->[0]->{id}, qr{\d+-\d+-\d+},
        'id element is present and in the form of an attachment id';
    is $response->[0]->{name}, 'Create-New-Page.png',
        'first element in sorted attachments is Create-New-Page.png';
    is $response->[3]->{name}, 'Navbar-Home.png',
        'fourth element in sorted attachments is Navbar-Home.png';

}

test_http "GET json from Workspace sorted size" {
    >> GET $WORKSPACE_BASE?order=size
    >> Accept: application/json

    << 200

    my $response = decode_json( $test->response->content );

    is $response->[0]->{name}, 'thing.png', 'first element in sorted attachments is thing.png';
    is $response->[11]->{name}, 'O Star.txt', 'fourth element in sorted attachments is O Star.txt';
}

my $attachment_uri;
while (my ($type, $body) = each %attachments) {
    test_http "POST then GET the DELETE $type" {
        >> POST $PAGE_BASE?name=funky.name
        >> Content-type: $type
        >>
        >> $body

        << 201
        ~< Location: ^http://[^/]+/data/workspaces/admin/attachments/[^/]+/files/funky.name$

        $attachment_uri = $test->response->header('location');

        >> GET $attachment_uri

        << 200
        ~< Content-type: \b$type\b
        <<
        << $body

        >> DELETE $attachment_uri

        << 204

        # put it back for later testing
        >> POST $PAGE_BASE?name=funky.name
        >> Content-type: $type
        >>
        >> $body

        << 201
        ~< Location: ^http://[^/]+/data/workspaces/admin/attachments/[^/]+/files/funky.name$

        $attachment_uri = $test->response->header('location');

    }
}

test_http "DELETE something not there" {
    >> DELETE $WORKSPACE_BASE/admin_wiki:200605071230-01

    << 404
}

test_http "POST without content type" {
    >> POST $PAGE_BASE?name=funky.name
    >>
    >> $attachments{'text/x.cowsay'}

    << 409

    my $body = $test->response->content();
    like $body, qr{Content-type header required},
        'error message with no content type';
}

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "attachment retrieval as bad user" {
    >> GET $attachment_uri

    << 403

    >> POST $PAGE_BASE?name=oh.yeah
    >> Content-Type: text/plain
    >>
    >> hello

    << 403

    >> DELETE $attachment_uri

    << 403

    >> GET $PAGE_BASE

    << 403
}
