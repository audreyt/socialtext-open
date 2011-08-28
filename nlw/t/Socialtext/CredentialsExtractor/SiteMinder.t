#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Test::Socialtext tests => 12;

###############################################################################
# Fixtures: empty
#
# Need to have the test User around.
fixtures(qw( empty ));

###############################################################################
## TEST DATA
###############################################################################
my $valid_username   = Test::Socialtext::User->test_username();
my $valid_user_id    = Socialtext::User->new(username => $valid_username)->user_id;
my $guest_user_id    = Socialtext::User->Guest->user_id;
my $bogus_username   = 'totally-bogus-unknown-user';
my $creds_extractors = 'SiteMinder:Guest';

Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

###############################################################################
# TEST: No SiteMinder credentials
no_credentials: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials from SiteMinder headers';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}

###############################################################################
# TEST: SiteMinder User, but no running session
siteminder_user_without_session: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        SM_USER => $valid_username,
    } );
    ok $creds->{valid}, 'extracted credentials from SiteMinder headers';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}

###############################################################################
# TEST: SiteMinder User, with a valid session
siteminder_user_in_session: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        SM_USER            => $valid_username,
        SM_SERVERSESSIONID => 'abc123',
    } );
    ok $creds->{valid}, 'extracted credentials from SiteMinder headers';
    is $creds->{user_id}, $valid_user_id, '... the expected User Id';
}

###############################################################################
# TEST: SiteMinder User, in "domain\username" format
siteminder_user_in_session_with_domain: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        SM_USER            => "DOMAIN\\$valid_username",
        SM_SERVERSESSIONID => 'abc123',
    } );
    ok $creds->{valid}, 'extracted credentials from SiteMinder headers';
    is $creds->{user_id}, $valid_user_id, '... the expected User Id';
}

###############################################################################
# TEST: SiteMinder session, but *without* a User (e.g. username provided in
# a different HTTP header)
siteminder_session_without_user: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        MISNAMED_SM_USER   => $valid_username,
        SM_SERVERSESSIONID => 'abc123',
    } );
    ok $creds->{valid}, 'extracted credentials from SiteMinder headers';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}

###############################################################################
# TEST: SiteMinder session, with unknown username
siteminder_unknown_user: {
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        SM_USER            => $bogus_username,
        SM_SERVERSESSIONID => 'abc123',
    } );
    ok !$creds->{valid}, 'failed to extract credentials from SiteMinder headers';
    like $creds->{reason}, qr/invalid username/, '... invalid Username';
}
