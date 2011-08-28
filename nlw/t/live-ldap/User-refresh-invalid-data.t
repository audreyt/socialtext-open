#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Socialtext::User;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 28;

###############################################################################
# FIXTURE:  db
#
# Need to have Pg running, but don't care what's in it.
fixtures(qw( db ));

###############################################################################
# TEST: refreshing LDAP User w/invalid data returns "last good data"
ldap_refresh_invalid_data_uses_last_good_data: {
    my $dn    = 'cn=Some User,dc=example,dc=com';
    my %attrs = (
        objectClass => 'inetOrgPerson',
        cn          => 'Some User',
        gn          => 'Some',
        sn          => 'User',
        title       => 'some.user@example.com',
    );

    # start up OpenLDAP
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $ldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # set custom LDAP config, so we can create Users with invalid data
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    # populate OpenLDAP schema
    ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';

    # create a "good" User in LDAP
    my $rc = $ldap->add($dn, %attrs);
    ok $rc, 'added test User to LDAP';

    # instantiate the User in ST, caching the data from LDAP
    my $cached_user = Socialtext::User->new(username => 'Some User');
    isa_ok $cached_user, 'Socialtext::User', 'LDAP test User';

    # remove the User's e-mail address in LDAP, so that our next lookup will
    # trigger a data validation error.
    $rc = $ldap->modify($dn, delete => [qw( title )]);
    ok $rc, 'cleared e-mail address in LDAP';

    # expire the User record, so we'll go back to LDAP on next lookup
    $cached_user->homunculus->expire();

    # re-instantiate the User in ST, wrapped in some sleeps so we can check
    # and make sure that it was refetched here
    clear_log();
    my $refetched_user;
    my $time_before = time();
    {
        sleep 2;

        $refetched_user = Socialtext::User->new(username => 'Some User');
        isa_ok $refetched_user, 'Socialtext::User', 'refetched LDAP test User';

        sleep 2;
    }
    my $time_after = time();

    # VERIFY: that we did fail to validate data when pulling from LDAP
    logged_like 'warning', qr/Email address is a required field/,
        '... which failed to refresh because e-mail was missing';

    # VERIFY: last_cached was set (even though we had troubles with lookup)
    my $refreshed_at = $refetched_user->cached_at->epoch();
    ok $refreshed_at > $time_before, '... User was marked as cached';
    ok $refreshed_at < $time_after,  '... ... when he was RE-fetched';

    # VERIFY: e-mail address was the last known good e-mail for the User
    is $refetched_user->email_address, $cached_user->email_address,
        '... e-mail address is same as before';
}

###############################################################################
# TEST: initial LDAP User fetch w/invalid data *does* throw an error
ldap_invalid_data_throws_error: {
    my $dn    = 'cn=Another User,dc=example,dc=com';
    my %attrs = (
        objectClass => 'inetOrgPerson',
        cn          => 'Another User',
        gn          => 'Another',
        sn          => 'User',
    );

    # start up OpenLDAP
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $ldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # set custom LDAP config, so we can create Users with invalid data
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    # populate OpenLDAP schema
    ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';

    # create a "bogus" User in LDAP
    my $rc = $ldap->add($dn, %attrs);
    ok $rc, 'added test User to LDAP';

    # instantiate the User in ST, which should fail on data validation
    my $user = eval { Socialtext::User->new(username => 'Another User') };
    ok !defined $user, 'failed to fetch LDAP User';

    my $e = Exception::Class->caught('Socialtext::Exception::DataValidation');
    ok $e, '... due to data validation error';
    like $e->full_message, qr/Email address is a required field/,
        '... ... missing e-mail address';
}

# Test: Duplicate email_address on refresh.
refresh_with_duped_email: {
    my $user1_dn = 'cn=Nathan Explosion,dc=example,dc=com';
    my %user1_attrs =  (
        objectClass => 'inetOrgPerson',
        mail        => 'nathan@example.com',
        cn          => 'Nathan Explosion',
        gn          => 'Nathan',
        sn          => 'Explosion',
        title       => 'Duped@example.com',
    );

    my $user2_dn = 'cn=Toki Wartooth,dc=example,dc=com';
    my %user2_attrs =  (
        objectClass => 'inetOrgPerson',
        mail        => 'toki@example.com',
        cn          => 'Toki Wartooth',
        gn          => 'Toki',
        sn          => 'Wartooth',
        title       => 'duped@example.com',
    );

    # start up OpenLDAP
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $ldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # populate OpenLDAP schema
    ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';

    # create first "bogus" User in LDAP
    my $rc = $ldap->add($user1_dn, %user1_attrs);
    ok $rc, 'added Nathan Explosion to LDAP';
    my $nathan = Socialtext::User->new(username => 'Nathan Explosion');
    ok $nathan->isa('Socialtext::User'), 'got Nathan Explosion';
    my $nathan_cached_at = $nathan->cached_at->epoch();

    # create second "bogus" User in LDAP
    $rc = $ldap->add($user2_dn, %user2_attrs);
    ok $rc, 'added Toki Wartooth to LDAP';
    my $toki = Socialtext::User->new(username => 'Toki Wartooth');
    ok $toki->isa('Socialtext::User'), 'got Toki Wartooth';
    my $toki_cached_at = $toki->cached_at->epoch();

    # update LDAP config, so we can refresh Users with invalid data
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    # expire Users
    $nathan->homunculus->expire();
    $toki->homunculus->expire();

    sleep 2; # stupid, but we need to ensure last_cached_at actually changes.

    # Refresh Toki, should work fine.
    my $toki_refreshed = Socialtext::User->new(username => 'Toki Wartooth');
    ok $toki_refreshed->isa('Socialtext::User'), 'Toki is still a user';
    is $toki_refreshed->email_address, 'duped@example.com',
        '... now has bad email_address';
    ok $toki_cached_at < $toki_refreshed->cached_at->epoch(),
        '... who has been properly refreshed.';

    # Refresh Nathan, should _not_ update.
    my $nathan_refreshed = Socialtext::User->new(username => 'Nathan Explosion');
    ok $nathan_refreshed->isa('Socialtext::User'), 'Nathan is still a user';
    is $nathan_refreshed->email_address, 'nathan@example.com',
        '... still has old email_address';
    ok $nathan_cached_at < $nathan_refreshed->cached_at->epoch(),
        '... who has been refreshed.';
}
