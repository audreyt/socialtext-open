#!perl

use strict;
use warnings;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Test::Socialtext tests => 17;

fixtures(qw( empty ));

my $valid_username   = Test::Socialtext::User->test_username();
my $valid_user_id    = Socialtext::User->new(username => $valid_username)->user_id;
my $creds_extractors = 'SSLCertificate:Guest';

Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

###############################################################################
# TEST: No SSL Certificate credentials
no_credentials: {
    my $guest_user_id = Socialtext::User->Guest->user_id;
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials, no SSL Cert';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}

###############################################################################
# TEST: Invalid format of SSL Certificate subject (bogus format)
invalid_subject_bogus_format: {
    my $subject = "CN: $valid_username is just bogus junk man";
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok !$creds->{valid}, 'failed to extract creds from invalid SSL Cert';
    like $creds->{reason}, qr/invalid certificate subject/, '... invalid cert';
}

###############################################################################
# TEST: Invalid format of SSL Certificate subject (missing CN field)
invalid_subject_missing_field: {
    my $subject = "C=US, ST=CA, L=Palo Alto, O=Socialtext, MAIL=$valid_username";
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok !$creds->{valid}, 'failed to extract creds when missing CN field';
    like $creds->{reason}, qr/invalid certificate subject/, '... invalid cert';
}

###############################################################################
# TEST: Valid cert, but the User doesn't exist
unknown_username: {
    my $subject = 'C=US, ST=CA, L=Palo Alto, O=Socialtext, CN=unknown_user@ken.socialtext.net';
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok !$creds->{valid}, 'failed to extract creds when User is unknown';
    like $creds->{reason}, qr/invalid username/, '... unknown Username';
}

###############################################################################
# TEST: Valid cert, slash-delimited Subject, User exists
valid_slash_delimited: {
    my $subject = "/C=US/ST=CA/L=Palo Alto/O=Socialtext/CN=$valid_username";
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok $creds->{valid}, 'extracted creds from slash delimited subject';
    is $creds->{user_id}, $valid_user_id, '... with valid User';
}

###############################################################################
# TEST: Valid cert, comma-delimited Subject, User exists
valid_comma_delimited: {
    my $subject = "C=US, ST=CA, L=Palo Alto, O=Socialtext, CN=$valid_username";
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok $creds->{valid}, 'extracted creds from comma delimited subject';
    is $creds->{user_id}, $valid_user_id, '... with valid User';
}

###############################################################################
# TEST: Valid cert updates User's "last login date"
updates_last_login: {
    my $guard  = Test::Socialtext::User->snapshot;
    my $user   = create_test_user();
    ok $user, 'Created test User';

    my $last_login = $user->last_login_datetime_object;
    is $last_login, DateTime::Infinite::Past->new, '... who has never logged in';

    # Extract creds for this User
    my $username = $user->username;
    my $subject  = "CN=$username";
    my $creds    = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok $creds->{valid}, 'extracted creds for User';
    is $creds->{user_id}, $user->user_id, '... the correct User';

    # VERIFY: last_login got updated for the User
    $user->reload;
    $last_login = $user->last_login_datetime_object;
    isnt $last_login, DateTime::Infinite::Past->new, '... login has been recorded';
}
