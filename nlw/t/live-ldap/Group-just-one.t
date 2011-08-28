#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Group::Factory;
use Socialtext::Group::LDAP::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 6;

# Force any LDAP Group lookups to be synchronous.
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
# Fixtures
fixtures(qw( db ));

###############################################################################
# Helpers
my $DefaultAcct = Socialtext::Account->Default;
my $SystemUser  = Socialtext::User->SystemUser;
my $MemberRole  = Socialtext::Role->Member;
my $AdminRole   = Socialtext::Role->Admin;
my $GroupDN     = 'cn=Motorhead,dc=example,dc=com';

###############################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),  'added people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), 'added groups';
    return $openldap;
}

###############################################################################
###############################################################################
# Bug 3519: Incorrect Group lookups when LDAP directory contains only one Group
###############################################################################
###############################################################################
# Buggy behaviour was that if you had *only one* Group available in LDAP, and
# had LDAP Groups enabled, that Group lookups would accidentally return this
# LDAP Group instead of the Group that you'd actually asked for.  Worse yet,
# this behaviour manifested even if you hadn't loaded that LDAP Group into the
# system; it would accidentally trigger a load of the LDAP Group into the
# system, thus accidentally loading all of the LDAP Users too.
dont_trigger_ldap_group_lookup: {
    # Bootstrap OpenLDAP, and set it up so that only *one* Group could be
    # available to us for lookup.
    my $openldap = bootstrap_openldap();
    my $config   = $openldap->ldap_config();
    $config->{group_filter} = '(&(cn=Motorhead)(objectClass=groupOfNames))';
    $openldap->add_to_ldap_config();

    # Verify that *only one* LDAP Group is available.
    my $driver   = $config->id();
    my $factory  = Socialtext::Group::LDAP::Factory->new(
        driver_key => "LDAP:$driver"
    );

    my $available = $factory->Available(all => 1);
    is $available, 1, 'Only one LDAP Group available';

    # Check that there are no LDAP Groups vivified into the system, do a Group
    # lookup (which would've triggered the buggy behaviour), and then
    # double-check that we _still_ have no LDAP Groups vivified into the
    # system.
    $available = $factory->Available();
    is $available, 0, '... and it has not been vivified yet';

    Socialtext::Group->GetGroup(group_id => 1);

    $available = $factory->Available();
    is $available, 0, '... Group lookup did *not* vivify Group by accident';
}
