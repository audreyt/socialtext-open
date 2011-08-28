#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 5;
use Socialtext::LDAP::Operations;
use Net::LDAP::Constant qw(LDAP_SIZELIMIT_EXCEEDED);

###############################################################################
# Fixture:  db
fixtures(qw( db ));

###############################################################################
# ERASE any existing LDAP config, so it doesn't pollute this test.
unlink Socialtext::LDAP::Config->config_filename();

###############################################################################
# Set up OpenLDAP, with a *custom* configuration:
# - enforce a soft limit of "max 10 items per search"
# - enforce a hard limit of "no more than 100 items in a search, *TOTAL*".
# Difference is that the soft limit controls how many results we can get back
# at one time, while the hard limit controls the total number of results that
# can be returned for the entire set.
#
# If you've got more than "hard limit" things you want to get back, you're
# screwed no matter what; the LDAP server *isn't* going to give you the
# results... you'll need to concoct a new query to ask in order to get those
# results.
my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new(
    raw_conf => "sizelimit size.soft=10 size.hard=100",
);
$openldap->add_ldif('t/test-data/ldap/base_dn.ldif');

###############################################################################
# Set up a different User to use to authenticate ourselves against the LDAP
# server; normally our test harness sets up the "root_dn" user for this, but
# in OpenLDAP that user has *unlimited* access.
#
# We want to test limits, thus... can't bind as the "root_dn" user.
my $bind_dn = 'cn=Bind User,dc=example,dc=com';
my $bind_pw = 'abc123';
$openldap->add( $bind_dn,
    objectClass  => 'inetOrgPerson',
    cn           => 'Bind User',
    gn           => 'Bind',
    sn           => 'User',
    mail         => 'bind-user@null.socialtext.net',
    userPassword => $bind_pw,
);
$openldap->ldap_config->bind_user($bind_dn);
$openldap->ldap_config->bind_password($bind_pw);
$openldap->add_to_ldap_config();

###############################################################################
# Add a bunch of Users to LDAP.
diag "Adding test Users to LDAP";
my $USERS_TO_ADD = 50;
foreach my $count (0 .. $USERS_TO_ADD) {
    my $gn = "Test";
    my $sn = "User $count";
    my $cn = "$gn $sn";
    my $dn = "cn=$cn,dc=example,dc=com";
    $openldap->add( $dn,
        objectClass  => 'inetOrgPerson',
        cn           => $cn,
        gn           => $gn,
        sn           => $sn,
        mail         => "test-user-$count\@null.socialtext.net",
        userPassword => 'bogus',
    ) || die "unable to add test data to LDAP";
}

###############################################################################
# Make sure that the soft limit works; if we do a raw search for all Users it
# should fail, telling us that we've exceeded the sizelimit for the search.
#
# This confirms for us that (a) the limit is in effect, and (b) that if the
# tests after this work properly that they're using a paged query.
verify_limit_is_in_effect: {
    my $ldap = Socialtext::LDAP->new();
    ok $ldap, 'Connected to LDAP';

    my $mesg = $ldap->search(
        base    => $ldap->config->base(),
        scope   => 'sub',
        filter  => '(objectClass=inetOrgPerson)',
        attrs   => '[*]',
    );
    ok $mesg, '... search returned a response';
    is $mesg->code, LDAP_SIZELIMIT_EXCEEDED, '... error: sizelimit exceeded';

    # CLEANUP
    Socialtext::Cache->clear();
}

###############################################################################
# TEST that we can load the Users from LDAP into ST.
load_users: {
    local $Socialtext::LDAP::Operations::LDAP_PAGE_SIZE = 10;
    my $before = Socialtext::User->Count();
    my $loaded = Socialtext::LDAP::Operations->LoadUsers();
    my $after  = Socialtext::User->Count();

    # Users we expect to have been loaded:
    #   = Users we added to LDAP
    #   + Bind User for LDAP (which we created above)
    #   + Root User for LDAP (added by ST:B:OpenLDAP)
    my $expected = $USERS_TO_ADD + 2;
    is $loaded, $expected, 'Loaded the correct number of Users from LDAP';
    is $after, ($before+$loaded), '... and overall User count matches too';

    # CLEANUP
    Socialtext::Cache->clear();
}
