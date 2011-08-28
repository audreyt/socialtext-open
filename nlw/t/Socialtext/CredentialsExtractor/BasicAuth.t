#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use MIME::Base64;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Test::Socialtext tests => 10;
use Test::Socialtext::User;

fixtures(qw( empty ));

###############################################################################
### TEST DATA
###############################################################################
my $valid_username = Test::Socialtext::User->test_username();
my $valid_password = Test::Socialtext::User->test_password();
my $valid_user_id  = Socialtext::User->new(username => $valid_username)->user_id;
my $guest_user_id  = Socialtext::User->Guest->user_id;

my $bad_username = 'unknown_user@socialtext.com';
my $bad_password = '*bad-password*';

my $creds_extractors = 'BasicAuth:Guest';

###############################################################################
# TEST: Username+password are correct, user can authenticate
correct_username_and_password: {
    my $authz_header = make_authz_header($valid_username, $valid_password);

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        AUTHORIZATION => $authz_header,
    } );
    ok $creds->{valid}, 'extracted credentials from REMOTE_USER';
    is $creds->{user_id}, $valid_user_id, '... with expected User Id';
}

###############################################################################
# TEST: Incorrect password, user cannot authenticate
incorrect_password: {
    my $authz_header = make_authz_header($valid_username, $bad_password);

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        AUTHORIZATION => $authz_header,
    } );
    ok !$creds->{valid}, 'failed to extract credentials from REMOTE_USER';
    like $creds->{reason}, qr/invalid/, '... invalid username/password';
}

###############################################################################
# TEST: Unknown username, user cannot authenticate
unknown_username: {
    my $authz_header = make_authz_header($bad_username, $bad_password);

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        AUTHORIZATION => $authz_header,
    } );
    ok !$creds->{valid}, 'failed to extract credentials from REMOTE_USER';
    like $creds->{reason}, qr/invalid/, '... invalid username/password';
}

###############################################################################
# TEST: Malformed Authorization header
malformed_header: {
    my $authz_header = make_authz_header($valid_username, "");

    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        AUTHORIZATION => $authz_header,
    } );
    ok !$creds->{valid}, 'failed to extract credentials from REMOTE_USER';
    like $creds->{reason}, qr/missing/, '... missing username/password';
}

###############################################################################
# TEST: No authentication header set, not authenticated
no_authentication_header_set: {
    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials from REMOTE_USER';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}



sub make_authz_header {
    my ($username, $password) = @_;
    my $encoded = MIME::Base64::encode("$username\:$password");
    return "Basic $encoded";
}
