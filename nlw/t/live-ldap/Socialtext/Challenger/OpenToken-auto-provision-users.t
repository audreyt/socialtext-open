#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::WebApp';
use mocked 'Apache::Cookie';
use mocked 'Socialtext::Hub';
use MIME::Base64;
use POSIX qw();
use Crypt::OpenToken;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::Challenger::OpenToken;
use Socialtext::User;
use Test::Socialtext tests => 4;
use Test::Socialtext::User;

###############################################################################
# Create our test fixtures *OUT OF PROCESS* as we're using a mocked Hub.
BEGIN {
    my $rc = system('dev-bin/make-test-fixture --fixture db');
    $rc >>= 8;
    $rc && die "unable to set up test fixtures!";
}
fixtures(qw( db ));

###############################################################################
# TEST DATA
###############################################################################
our %data = (
    challenge_uri => 'http://www.google.com',
    password      => 'a66C9MvM8eY4qJKyCXKW+19PWDeuc3th',
);

sub bootstrap_openldap {
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    $ldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $ldap->add_ldif('t/test-data/ldap/people.ldif');
    return $ldap;
}


###############################################################################
# TEST: Don't auto-provision LDAP Users
dont_update_ldap_users: {
    my $guard    = Test::Socialtext::User->snapshot();
    my $openldap = bootstrap_openldap();
    my $user     = Socialtext::User->new(username => 'John Doe');
    ok $user, 'Got User from LDAP';

    my $rc = _issue_auto_provisioning_challenge(
        with_user => {
            username      => $user->username,
            email_address => $user->email_address,
            first_name    => 'Jane',
            last_name     => 'Smith',
        },
    );
    ok $rc, '... challenge was successful';

    # Verify that we've got the LDAP info for that User.
    my $refreshed = Socialtext::User->new(username => 'John Doe');
    is $refreshed->first_name, 'John', '... with first_name from LDAP';
    is $refreshed->last_name,  'Doe',  '... with last_name from LDAP';
}





sub _issue_auto_provisioning_challenge {
    my %args = @_;
    my $user_data = $args{with_user};

    # save the configuration, allowing for explicit over-ride of config text
    my $config = Socialtext::OpenToken::Config->new(
        %data,
        auto_provision_new_users => 1,
    );
    Socialtext::OpenToken::Config->save($config);

    # set a Guest user (so that it *looks like* we're not a valid user)
    my $hub = Socialtext::Hub->new;
    $hub->{current_user} = Socialtext::User->Guest();

    # cleanup prior to test run
    Socialtext::WebApp->clear_instance();
    Apache::Cookie->clear_cookies();

    # in an OpenToken, the "subject" parameter *is* the username
    $user_data->{subject} = delete $user_data->{username};

    # create an OpenToken to use for the challenge
    my $password = decode_base64($data{password});
    my $factory  = Crypt::OpenToken->new(password => $password);
    my $token   = $factory->create(
        Crypt::OpenToken::CIPHER_AES128,
        $user_data,
    );

    my $token_param = $config->token_parameter;
    local $Apache::Request::PARAMS{$token_param} = $token;

    # issue the challenge
    my $rc = Socialtext::Challenger::OpenToken->challenge(hub => $hub);
    return $rc;
}

sub _make_iso8601_date {
    my $time_t = shift;
    return POSIX::strftime('%Y-%m-%dT%H:%M:%SGMT', gmtime($time_t));
}
