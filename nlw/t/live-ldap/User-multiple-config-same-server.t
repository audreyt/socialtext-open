#!/usr/bin/env perl
use strict;
use warnings;

# One LDAP server, multiple configs pointing to the different bases within
# that server. Make sure that we find users under the correct config.

use Test::More;
use Test::Socialtext;
use Socialtext::User;
use Socialtext::LDAP::Config;
use Socialtext::LDAP::Operations;
use Clone 'clone';
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User::LDAP::Factory;

fixtures('db');

$Socialtext::LDAP::CacheEnabled = 0;
$Socialtext::User::Cache::Enabled = 0;
$Socialtext::User::LDAP::Factory::CacheEnabled = 0;

my $ldap;
my $user;
my ($people, $terminated);
my $user_dn = 'cn=Warren Maxwell,ou=people,dc=foo,dc=com';

setup: {
    $ldap = initialize_ldap('foo');
    $ldap->add(
        'ou=people,dc=foo,dc=com',
        objectClass => 'organizationalUnit',
        description => ' current employees',
        ou => 'people',
    );
    $ldap->add(
        'ou=terminated,dc=foo,dc=com',
        objectClass => 'organizationalUnit',
        description => ' current employees',
        ou => 'terminated',
    );
    $ldap->add(
        $user_dn,
        objectClass => 'inetOrgPerson',
        cn => 'Warren Maxwell',
        gn => 'Warren',
        sn => 'Maxwell',
        mail => 'warren@example.com',
        userPassword => 'password',
    );
    $people = $ldap->ldap_config->id;
    $terminated = Socialtext::LDAP::Config->generate_driver_id();

    my $people_config = Socialtext::LDAP::Config->load();
    $people_config->{base} = 'ou=people,dc=foo,dc=com';
    $people_config->{id} = $people;

    my $terminated_config = clone($people_config);
    $terminated_config->{base} = 'ou=terminated,dc=foo,dc=com';
    $terminated_config->{id} = $terminated;

    my $rc = Socialtext::LDAP::Config->save($people_config, $terminated_config);
    ok $rc, 'saved ldap.yaml';
}

set_user_factories("LDAP:$people", 'Default');
$user = Socialtext::User->new(username=>'warren maxwell');
ok $user, 'instantiated a user';
is $user->homunculus->driver_unique_id, $user_dn, 'got correct id';
is $user->homunculus->driver_key, "LDAP:$people", 'got people driver';

Socialtext::LDAP::Operations->RefreshUsers(username=>'warren maxwell',force=>1);
$user = Socialtext::User->new(username=>'warren maxwell');
ok $user, 'instantiated a user';
is $user->homunculus->driver_unique_id, $user_dn, 'got correct id';
is $user->homunculus->driver_key, "LDAP:$people", 'got people driver';

set_user_factories("LDAP:$terminated", "LDAP:$people", 'Default');
Socialtext::LDAP::Operations->RefreshUsers(username=>'warren maxwell',force=>1);
$user = Socialtext::User->new(username=>'warren maxwell');
ok $user, 'instantiated a user';
is $user->homunculus->driver_unique_id, $user_dn, 'got correct id';
is $user->homunculus->driver_key, "LDAP:$people", 'got people driver';

done_testing;
