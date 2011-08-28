#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::HTTP::Socialtext '-syntax', tests => 18;
use Readonly;
use Socialtext::JSON;
use Test::Live fixtures => ['admin', 'foobar'];
use Test::More;
use URI;

Readonly my $BASE => Test::HTTP::Socialtext->url('/data/users');

TODO: {
    local $TODO = 'write this';

    test_http "DELETE users is a bad method" {
        >> DELETE $BASE

        << 405
        << Allow: GET, POST
    }

    test_http "GET html default" {
        >> GET $BASE

        << 405
    }

    test_http "GET json" {
        >> GET $BASE
        >> Accept: application/json

        << 405
    }
}

# Since the above is all TODO, add just one specific user entry we want to
# look at.

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "GET devnull2 JSON as devnull2" {
    >> GET $BASE/devnull2\@socialtext.com
    >> Accept: application/json

    << 200
    ~< Content-type: \bapplication/json\b

    my $result = eval { decode_json($test->response->content) };
    is( $@, '', 'JSON is legit.' );
    isa_ok( $result, 'HASH', 'JSON response' );

    is_deeply(
        [ sort keys %$result ],
        [ qw(
            created_by_user_id
            creation_datetime
            email_address
            email_address_at_import
            first_name
            is_business_admin
            is_system_created
            is_technical_admin
            last_login_datetime
            last_name
            user_id
            username
        ) ],
        'User has the correct keys.'
    );
}

# Current implementation 404s when a user doesn't have permission to
# view another user
$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "GET fail devnull1 JSON as devnull2 and fail" {
    >> GET $BASE/devnull1\@socialtext.com
    >> Accept: application/json

    << 404
}

test_http "GET devnull2 JSON as devnull2" {
    >> GET $BASE/devnull2\@socialtext.com
    >> Accept: application/json

    << 200
}

$Test::HTTP::BasicUsername = 'devnull1@socialtext.com';
test_http "GET devnull1 JSON as devnull1 and succeed" {
    >> GET $BASE/devnull1\@socialtext.com
    >> Accept: application/json

    << 200
}

$Test::HTTP::BasicUsername = 'devnull1@socialtext.com';
test_http "GET devnull2 JSON as devnull1 and succeed" {
    >> GET $BASE/devnull2\@socialtext.com
    >> Accept: application/json

    << 200
}

my $NEW_USER_URL = Test::HTTP::Socialtext->url("/data/users");
my $username = 'my-user@socialtext.com';
my $USER_CREATION_JSON =
  encode_json( {
              username => $username,
              email_address => $username,
              first_name => 'my',
              last_name => 'user',
             } );

# make sure we're the business admin                                   
$Test::HTTP::BasicUsername = 'devnull1@socialtext.com';

test_http "POST new user returns 201 and location" {
    >> POST $NEW_USER_URL
    >> Content-Type: application/json
    >>
    >> $USER_CREATION_JSON

    << 201
    ~< Location: $NEW_USER_URL/$username
}

test_http "POST existing user returns 201 and location" {
    >> POST $NEW_USER_URL
    >> Content-Type: application/json
    >>
    >> $USER_CREATION_JSON

    << 400
    <<
    ~< username you provided .* is already in use
}


$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';

test_http "POST new user forbidden for non-business admin" {
    >> POST $NEW_USER_URL
    >> Content-type: application/json
    >>
    >> $USER_CREATION_JSON

    << 401
}
