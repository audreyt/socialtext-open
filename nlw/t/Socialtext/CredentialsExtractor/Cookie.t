#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Digest::SHA;
use Socialtext::HTTP::Cookie qw(USER_DATA_COOKIE AIR_USER_COOKIE);
use Socialtext::AppConfig;
use Socialtext::CredentialsExtractor;
use Test::Socialtext tests => 10;
use Test::Socialtext::User;

###############################################################################
# Fixtures: empty
#
# Need to have the test User around.
fixtures(qw( empty ));

###############################################################################
### TEST DATA
###############################################################################
my $valid_username  = Test::Socialtext::User->test_username();
my $valid_user_id   = Socialtext::User->new(username => $valid_username)->user_id;
my $guest_user_id   = Socialtext::User->Guest->user_id;
my $cookie_name     = USER_DATA_COOKIE();
my $air_cookie_name = AIR_USER_COOKIE();
my $air_user_agent  = 'Mozilla/5.0 (Windows; U; en) AppleWebKit/420+ (KHTML, like Gecko) AdobeAIR/1.0';

my $creds_extractors = 'Cookie:Guest';

sub sudo_make_me_a_cookie {
    my $name  = shift;
    my $value = shift;
    return "$name=$value";
}

###############################################################################
# TEST: Cookie present, user can authenticate
cookie_ok: {
    # create the cookie data
    my $cookie = sudo_make_me_a_cookie(
        $cookie_name,
        Socialtext::HTTP::Cookie->BuildCookieValue(user_id => $valid_user_id),
    );

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        COOKIE => $cookie,
    } );
    ok $creds->{valid}, 'extracted credentials from HTTP cookie';
    is $creds->{user_id}, $valid_user_id, '... the expected User Id';
}

###############################################################################
# TEST: Cookie present, but invalid
cookie_invalid: {
    # create the cookie data
    my $cookie = sudo_make_me_a_cookie(
        $cookie_name,
        'THIS-IS-A-BAD-COOKIE',
    );

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        COOKIE => $cookie,
    } );
    ok !$creds->{valid}, 'unable to extract credentials from HTTP cookie';
    like $creds->{reason}, qr/invalid/, '... invalid cookie';
}

###############################################################################
# TEST: Cookie missing, not authenticated
cookie_missing: {
    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials from HTTP cookie';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}

###############################################################################
# TEST: AIR client does NOT share standard HTTP cookie
adobe_air_separate_cookie: {
    # create the cookie data
    my $cookie = sudo_make_me_a_cookie(
        $cookie_name,
        Socialtext::HTTP::Cookie->BuildCookieValue(user_id => $valid_user_id),
    );
    my $air_cookie = sudo_make_me_a_cookie(
        $air_cookie_name,
        Socialtext::HTTP::Cookie->BuildCookieValue(user_id => $valid_user_id),
    );

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # TEST: AIR client doesn't get to use standard HTTP cookie
    {
        my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
            USER_AGENT => $air_user_agent,
            COOKIE     => $cookie,
        } );
        ok $creds->{valid}, 'extracted credentials from AIR cookie';
        is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
    }

    # TEST: AIR client uses its own HTTP cookie
    {
        my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
            USER_AGENT => $air_user_agent,
            COOKIE     => $air_cookie,
        } );
        ok $creds->{valid}, 'extracted credentials from AIR cookie';
        is $creds->{user_id}, $valid_user_id, '... the expected User Id';
    }
}
