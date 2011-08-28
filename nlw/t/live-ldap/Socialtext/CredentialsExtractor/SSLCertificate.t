#!perl

###
###
### Other test cases for the SSLCertificate Credentials Extractor exist
### over in 't/Socialtext/CredentialsExtractor/SSLCertificate.t'
###
### Here, we're *just* testing the interaction w/LDAP.
###
###

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::CredentialsExtractor;
use Socialtext::AppConfig;
use Test::Socialtext tests => 2;

fixtures(qw( empty ));

my $creds_extractors = 'SSLCertificate:Guest';
Socialtext::AppConfig->set(credentials_extractors => $creds_extractors);

sub bootstrap_openldap {
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    $ldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $ldap->add_ldif('t/test-data/ldap/people.ldif');
    return $ldap;
}

###############################################################################
# TEST: Valid cert, LDAP sourced User
valid_ldap_sourced_user: {
    my $ldap     = bootstrap_openldap();
    my $username = 'Bubba Bo Bob Brain';
    my $user     = Socialtext::User->new(username => $username);
    my $subject  = "C=US, ST=CA, O=Socialtext, CN=$username";

    my $creds = Socialtext::CredentialsExtractor->ExtractCredentials( {
        X_SSL_CLIENT_SUBJECT => $subject,
    } );
    ok $creds->{valid}, 'extracted creds and found LDAP sourced User';
    is $creds->{user_id}, $user->user_id, '... the expected User';
}
