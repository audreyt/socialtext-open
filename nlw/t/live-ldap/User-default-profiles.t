#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 3;
use Test::Socialtext::User;

# Explicitly load these, so we *know* they're loaded (instead of just waiting
# for them to be lazy loaded); we need to set some pkg vars for testing
use Socialtext::People::Profile;
use Socialtext::People::Fields;

# We're destructive, as we monkey around with the People Fields setup for the
# Default Account.  *Far* easier to just mark ourselves as destructive than it
# is to do this cleanly.
fixtures(qw( db destructive ));

###############################################################################
# Force People Profile Fields to be automatically created, so we don't have to
# set up the default sets of fields from scratch.
$Socialtext::People::Fields::AutomaticStockFields=1;

###############################################################################
# Make *ALL* profile lookups synchronous (easier testing)
$Socialtext::Pluggable::Plugin::People::Asynchronous=0;

###############################################################################
sub bootstrap_openldap {
    my %p = @_;

    # Bootstrap LDAP, but leave all of the Profile Fields as being internally
    # sourced (so we shouldn't *ever* be pulling them from LDAP).
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    $openldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $openldap->add_ldif('t/test-data/ldap/relationships.ldif');

    # Update LDAP config to map the "supervisor" and "work_phone" fields so
    # that they have LDAP mappings.
    my $config = $openldap->ldap_config();
    $config->{attr_map}{supervisor} = 'manager';
    $config->{attr_map}{work_phone} = 'telephoneNumber';
    Socialtext::LDAP::Config->save($config);

    return $openldap;
}

###############################################################################
# TEST: instantiating User should *NOT* pull "user sourced" Profile Fields
instantiate_should_not_pull_user_sourced_fields: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = bootstrap_openldap();

    my $user = Socialtext::User->new(username => 'Ariel Young');
    ok $user, 'loaded User with a supervisor';

    my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse=>1);
    ok $profile, 'got People Profile';

    my $phone = $profile->get_attr('work_phone');
    ok !$phone, '... with empty work_phone';
}

