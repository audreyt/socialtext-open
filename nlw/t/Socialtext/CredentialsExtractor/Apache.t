#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Test::Socialtext tests => 4;
use Test::Socialtext::User;

###############################################################################
# Fixtures: empty
#
# Need to have the test User around.
fixtures(qw( empty ));

###############################################################################
### TEST DATA
###############################################################################
my $valid_username = Test::Socialtext::User->test_username();
my $valid_user_id  = Socialtext::User->new(username => $valid_username)->user_id;
my $guest_user_id  = Socialtext::User->Guest->user_id;

my $creds_extractors = 'Apache:Guest';

###############################################################################
# TEST: Apache has authenticated User
apache_has_authenticated: {
    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        REMOTE_USER => $valid_username,
    } );
    ok $creds->{valid}, 'extracted credentials from Apache';
    is $creds->{user_id}, $valid_user_id, '... with expected User Id';
}

###############################################################################
# TEST: Apache has not authenticated User
apache_has_not_authenticated: {
    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials from Apache';
    is $creds->{user_id}, $guest_user_id, '... the Guest; fall-through';
}
