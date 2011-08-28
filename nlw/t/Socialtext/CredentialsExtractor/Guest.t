#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Socialtext::User;
use Test::Socialtext tests => 2;

###############################################################################
# Fixtures: base_config
#
# Need to have the config files present/available, but don't need anything
# else.
fixtures(qw( base_config ));

###############################################################################
### TEST DATA
###############################################################################
my $creds_extractors = 'Guest';
my $guest_user_id    = Socialtext::User->Guest->user_id;

###############################################################################
# TEST: Always fails to authenticate
guest_is_always_failure: {
    # configure the list of Credentials Extractors to run
    Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

    # extract the credentials
    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( { } );
    ok $creds->{valid}, 'extracted credentials';
    is $creds->{user_id}, $guest_user_id, '... the Guest';
}
