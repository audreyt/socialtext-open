#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 11;
use Socialtext::User;
use Socialtext::User::LDAP::Factory;

fixtures(qw( db ));

###############################################################################
###############################################################################
###
### This test case tries to exercise a scenario that one of our customers
### spoke to Support about recently...
###
### They had a User who was previously able to log in to the system.  This
### User left the company and later came back, and a new record was created
### for them within their LDAP directory... with the *SAME* e-mail that the
### old record  had.  Further, the old record was *STILL* present in the
### directory; it wasn't removed, deleted, or filed away, but was still
### exactly where we expected to find it.
###
### Result?  Two LDAP User records with the same e-mail address; User was
### unable to log in.
###
### Proposed Solution:  We recommended that they update the "filter" in their
### LDAP configuration so that we could filter out that old User record.
###
###############################################################################
###############################################################################

###############################################################################
# TEST: what happens when we've got two Users in LDAP with the same e-mail
# address?
user_with_duplicate_email_in_ldap: {
    my $email = 'test.user@example.com',
    my $first_user_dn = 'cn=First User,dc=example,dc=com';
    my $second_user_dn = 'cn=Second User,dc=example,dc=com';

    # Bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'Bootstrapped OpenLDAP';
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'),
        '... added data: base_dn';

    # Turn *OFF* in-memory caches, so we know that all lookups go back to the
    # LDAP server.
    $Socialtext::LDAP::CacheEnabled = 0;
    $Socialtext::User::Cache::Enabled = 0;
    $Socialtext::User::LDAP::Factory::CacheEnabled = 0;

    # Add a User to LDAP, and vivify them into ST.
    my $rc = $openldap->add(
        $first_user_dn,
        objectClass     => 'inetOrgPerson',
        cn              => 'First User',
        gn              => 'First',
        sn              => 'User',
        mail            => $email,
        userPassword    => 'abc123',
    );
    ok $rc, 'Added first test User to LDAP';

    my $first_user = Socialtext::User->new( email_address => $email );
    isa_ok $first_user, 'Socialtext::User', '... found first test User';
    is $first_user->first_name, 'First', '... ... and it *is* First User';

    # Add another User to LDAP with the *SAME* e-mail address.
    $rc = $openldap->add(
        $second_user_dn,
        objectClass     => 'inetOrgPerson',
        cn              => 'Second User',
        gn              => 'Second',
        sn              => 'User',
        mail            => $email,
        userPassword    => 'abc123',
    );
    ok $rc, 'Added second test User to LDAP';

    # Attempt to re-vivify the User; we should *FAIL*, complaining about
    # having found multiple Users in LDAP with the same e-mail address.
    clear_log();

    my $lookup = Socialtext::User->new( email_address => $email );
    isa_ok $lookup, 'Socialtext::User', 'found a user searching by email';
    is $lookup->driver_unique_id, $first_user_dn, 'found first user';

    # Tweak the LDAP config, to try to hide the first User.
    $openldap->ldap_config->{filter} = '(&(objectClass=inetOrgPerson)(!(gn=First)))';
    ok $openldap->add_to_ldap_config(),
        '... LDAP config updated to filter out First User';

    # Attempt to re-vivify the User; we should *SUCCEED* this time as we've
    # hidden the first User from view.
    my $second_user = Socialtext::User->new( email_address => $email );
    isa_ok $second_user, 'Socialtext::User', '... found second test User';
    is $second_user->first_name, 'Second', '... ... and it *is* Second User';
}
