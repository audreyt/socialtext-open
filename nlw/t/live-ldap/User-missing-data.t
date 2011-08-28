#!/usr/bin/env perl
# @COPYRIGHT@

###############################################################################
#
# ISSUE: if the LDAP entry is missing some of the data, it would throw an
# exception.  Default Users were allowed to have some fields blank (e.g. first
# name, last name), but LDAP Users were not.
#
# SCOPE: Many of our customers experience this problem right now.
#  * Pointroll
#  * ATSU ( will in the future. )
#  * ABC
# Making sure this use case is covered in tests so we can fix it some day.

# RESOLUTION: LDAP Users should be allowed to have the same set of blank
# fields that Default Users do
#
###############################################################################

use strict;
use warnings;
use Socialtext::LDAP;
use Socialtext::User;
use Socialtext::User::Default::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Warn;
use Test::Socialtext tests => 7;

fixtures( 'db' );

###############################################################################
# Fire up LDAP, and populate it with some users.
my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
isa_ok $ldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

# ... custom config, so that we can set the "last name" to a field that could
#     be null
$ldap->ldap_config->{attr_map}{last_name} = 'title';
$ldap->add_to_ldap_config();

# ... populate OpenLDAP
ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
ok $ldap->add_ldif('t/test-data/ldap/people.ldif'), 'added people';

# Add 'good' data.
$ldap->add(
    'cn=No Name,dc=example,dc=com',
    objectClass  => 'inetOrgPerson',
    cn           => 'No Name',
    gn           => 'No',
    title        => 'Name',
    sn           => 'UNUSED',
    mail         => 'no.name@example.com',
    userPassword => 'foobar'
);

# This is our 'happy path'.
my $user = Socialtext::User->new( email_address => 'no.name@example.com' );
isa_ok $user, 'Socialtext::User';
isnt $user->last_name, '', '... and has a last_name';

# This tests a null last_name field.
my $other_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
isa_ok $other_user, 'Socialtext::User';
is $other_user->last_name, '', '... and has a blank last_name';
