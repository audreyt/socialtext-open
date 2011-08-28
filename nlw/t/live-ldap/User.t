#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::LDAP;
use Socialtext::User;
use Socialtext::User::Default::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::SQL qw/sql_execute/;
use Test::Warn;
use Test::Socialtext tests => 41;

fixtures( 'db' );

$Socialtext::User::Default::Factory::CacheEnabled = 0;

###############################################################################
### TEST DATA
###
### Create a test user in the Default user store (Pg) that conflicts with one
### of the users in our LDAP test data.
###############################################################################
my $default_user = Socialtext::User->create(
    username         => 'John Doe',
    email_address    => 'john.doe@example.com',
    password         => 'pg-password',
);
is $default_user->homunculus->driver_key, 'Default',
    'user created in Default store';

sub bootstrap_tests {
    my $filter = shift;
    my $populate = shift || 'people';

    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # save LDAP config to YAML
    my $config = $openldap->ldap_config();
    if ($filter) {
        $config->filter($filter);
        is $config->filter, $filter, '... set filter';
    }
    ok $openldap->add_to_ldap_config(), 'saved custom LDAP config to YAML';

    # populate OpenLDAP with users
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif("t/test-data/ldap/$populate.ldif"), 'added data; people';

    return [$openldap, $config];
}

###############################################################################
# Instantiate user from LDAP, even when one exists in PostgreSQL.
# - want to make sure that if LDAP is the first declared factory, that it
#   picks up the user from here first
instantiate_user_from_ldap_even_when_exists_in_postgresql: {
    my $refs = bootstrap_tests();

    # instantiate user; should get from LDAP, not Pg
    my $user = Socialtext::User->new(username => 'John Doe');
    isa_ok $user, 'Socialtext::User', 'instantiated user';
    is $user->driver_name(), 'LDAP', '... with LDAP driver';
    isa_ok $user->homunculus(), 'Socialtext::User::LDAP', '... and LDAP homunculus';
}

###############################################################################
# Instantiate user from PostgreSQL, when only contact exists in LDAP
# - want to make sure that if LDAP contains a non-user entry that we pick up
#   the user from PostgreSQL (even if LDAP is the first factory)
instantiate_user_from_postgresql_when_only_contact_in_ldap: {
    my $refs = bootstrap_tests('(objectClass=inetOrgPerson)', 'contacts');

    # Forcefully convert back to a default user.
    my $user = Socialtext::User->new(username => 'John Doe');
    sql_execute(qq{
        UPDATE users
           SET driver_key = ?,
               driver_unique_id = ?,
               missing = ?
         WHERE user_id = ?
    }, 'Default', $user->user_id, '0', $user->user_id);
    Socialtext::User::Cache->Remove(user_id => $user->user_id);

    $user = Socialtext::User->new(username => 'John Doe');
    # instantiate user; should get from Pg, not LDAP
    isa_ok $user, 'Socialtext::User', 'instantiated user';
    is $user->driver_name(), 'Default', '... with Default driver';
    isa_ok $user->homunculus(), 'Socialtext::User::Default', '... and Default homunculus';
}

###############################################################################
# LDAP users *NEVER* have a password field in the homunculus; we *DON'T* grab
# that info from the LDAP store.
#
# This test was designed to deal with a bug where if a customer misconfigured
# their `ldap.yaml` file to list a password attribute *and* they had a poorly
# configured LDAP directory, we _could_ be pulling the (encrypted) password
# attribute for users from the directory.
ldap_users_have_no_password: {
    my $refs = bootstrap_tests();

    # instantiate LDAP user.
    my $user = Socialtext::User->new(
        username => 'John Doe',
        );
    isa_ok $user, 'Socialtext::User', 'instantiated user';
    is $user->driver_name(), 'LDAP', '... with LDAP driver';

    # make sure the LDAP homunculus has "*no-password*"
    my $homunculus = $user->homunculus();
    isa_ok $homunculus, 'Socialtext::User::LDAP', '... and LDAP homunculus';
    is $homunculus->{password}, '*no-password*', '... and *no-password* (data)';
    is $homunculus->password, '*no-password*', '... and *no-password* (accessor)';
}

###############################################################################
# Auto-vivify a LDAP user.
auto_vivify_an_ldap_user: {
    my $refs = bootstrap_tests();

    my $id_before = Socialtext::User::Factory->NewUserId();

    # instantiate LDAP user.
    my $user = Socialtext::User->new(
        username => 'Jane Smith'
    );
    isa_ok $user, 'Socialtext::User', 'instantiated user';
    is $user->driver_name(), 'LDAP', '... with LDAP driver';
    my $id_after = Socialtext::User::Factory->NewUserId();

    ok $user->user_id > $id_before, '... has a user_id';
    ok $user->user_id < $id_after, '... not a spontaneous id';

    # make sure the LDAP homunculus has "*no-password*"
    my $homunculus = $user->homunculus();
    isa_ok $homunculus, 'Socialtext::User::LDAP', '... and LDAP homunculus';
    is $homunculus->{password}, '*no-password*', '... and *no-password*';
}

deactivate_an_ldap_user: {
    my $refs = bootstrap_tests();

    my $user = Socialtext::User->new(username => 'Ray Parker');
    isa_ok $user, 'Socialtext::User', 'got a user';

    warnings_like { $user->deactivate }
        [
            qr/The user has been removed from workspaces and directories/,
            qr/Login information is controlled by the LDAP directory administrator./
        ],
        'warning on deactivate.';
}
