#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Slurp qw(slurp write_file);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 26;
use Test::Socialtext::User;

###############################################################################
# FIXTURE: db
#
# Need Pg running, but we don't care what's in it.
fixtures( 'db' );

###############################################################################
# Authenticate, with LDAP referrals enabled; should succeed
authenticate_with_referrals: {
    diag "TEST: authenticate_with_referrals";
    my $guard = Test::Socialtext::User->snapshot();

    # set up the OpenLDAP servers
    my ($ldap_src, $ldap_tgt) = setup_ldap_servers_with_referrals();

    # find user record; should succeed
    my $user = Socialtext::User->new( username => 'John Doe' );
    isa_ok $user, 'Socialtext::User', 'found user';
    is $user->driver_name(), 'LDAP', '... in LDAP store';

    # authenticate as the user
    ok $user->password_is_correct('foobar'), '... authen w/correct password';
    ok !$user->password_is_correct('BADPASS'), '... authen w/bad password';
}

###############################################################################
# Authenticate, with LDAP referrals disabled; should fail
authenticate_no_referrals: {
    diag "TEST: authenticate_no_referrals";
    # set up the OpenLDAP servers
    my ($ldap_src, $ldap_tgt) = setup_ldap_servers_with_referrals();

    # update LDAP config, disabling support for LDAP referrals
    $ldap_src->ldap_config->follow_referrals(0);
    ok $ldap_src->add_to_ldap_config(), 'disabled LDAP referrals in LDAP config';

    # find user record; should fail
    my $user = Socialtext::User->new( username => 'John Doe' );
    ok !$user, 'did not find user';
}

###############################################################################
# Search, with LDAP referrals enabled; should return list of users
search_with_referrals: {
    diag "TEST: search_with_referrals";
    # set up the OpenLDAP servers
    my ($ldap_src, $ldap_tgt) = setup_ldap_servers_with_referrals();

    # search for users; should succeed
    my @users = Socialtext::User->Search('john');
    is scalar(@users), 1, 'search returned a single user';

    my $user = shift @users;
    like $user->{driver_name}, qr/^LDAP:/, '... in LDAP store';
}

###############################################################################
# Search, with LDAP referrals disabled; should return empty-handed
search_no_referrals: {
    diag "TEST: search_no_referrals";
    # set up the OpenLDAP servers
    my ($ldap_src, $ldap_tgt) = setup_ldap_servers_with_referrals();

    # update LDAP config, disabling support for LDAP referrals
    $ldap_src->ldap_config->follow_referrals(0);
    ok $ldap_src->add_to_ldap_config(), 'disabled LDAP referrals in LDAP config';

    # search for users; should return empty handed
    my @users = Socialtext::User->Search('john');
    ok !@users, 'no users returned from search';
}

###############################################################################
# Set up our OpenLDAP servers, with referral data.
#
# *ALL* queries issued against the configured LDAP user factory will result in
# a referral response.
sub setup_ldap_servers_with_referrals {
    # bootstrap the OpenLDAP referral target
    my $openldap_target = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap_target, 'Test::Socialtext::Bootstrap::OpenLDAP', 'referral target';

    my $target_host = $openldap_target->host();
    my $target_port = $openldap_target->port();

    # bootstrap the OpenLDAP referral source; *ALL* queries issued against
    # this will result in an LDAP referral response
    my $openldap_source = Test::Socialtext::Bootstrap::OpenLDAP->new(
        raw_conf => "referral ldap://${target_host}:${target_port}",
        nodb     => 1,
    );
    isa_ok $openldap_source, 'Test::Socialtext::Bootstrap::OpenLDAP', 'referral source';

    # remove the LDAP config for the referral *target*; the only way we get
    # there is through a referral (*not* through our config)
    $openldap_target->remove_from_user_factories();
    $openldap_target->remove_from_ldap_config();

    # populate OpenLDAP servers with data
    ok $openldap_target->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn to referral target';
    ok $openldap_target->add_ldif('t/test-data/ldap/people.ldif'),  'added people to referral target';

    # return the OpenLDAP instances back to the caller
    return ($openldap_source, $openldap_target);
}
