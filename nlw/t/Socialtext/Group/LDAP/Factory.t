#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 2;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it
fixtures(qw( db ));

###############################################################################
# TEST: instantiation with unknown LDAP driver_id
instantiation_unknown_driver_id: {
    my $factory = Socialtext::Group->Factory(
        driver_key => 'LDAP:0xDEADBEEF',
    );
    ok !defined $factory, 'Unable to instantiate bogus LDAP Group Factory';
}

###############################################################################
# TEST: instantiation with valid LDAP driver_id
instantiation_valid_driver_id: {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    my $ldap_id  = $openldap->ldap_config->id;
    my $factory  = Socialtext::Group->Factory(
        driver_key => "LDAP:$ldap_id",
    );

    isa_ok $factory, 'Socialtext::Group::LDAP::Factory',
        'Instantiated LDAP Group Factory';
}
