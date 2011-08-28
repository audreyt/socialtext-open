#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User;
use Socialtext::User::LDAP::Factory;
use Socialtext::User::Default::Factory;

fixtures('db');

$Socialtext::LDAP::CacheEnabled = 0;
$Socialtext::User::Cache::Enabled = 0;
$Socialtext::User::LDAP::Factory::CacheEnabled = 0;
$Socialtext::User::Default::Factory::CacheEnabled = 0;

my ($foo,$bar); # LDAP stores.
my ($user, $user_id); # test user

setup: {
    $foo = initialize_ldap('foo');
    $foo->add(
        'cn=Warren Maxwell,dc=foo,dc=com',
        objectClass => 'inetOrgPerson',
        cn => 'Warren Maxwell',
        gn => 'Warren',
        sn => 'Maxwell',
        mail => 'warren@example.com',
        userPassword => 'password',
    );

    $bar = initialize_ldap('bar');
    $bar->add(
        'cn=Warren Maxwell,dc=bar,dc=com',
        objectClass => 'inetOrgPerson',
        cn => 'Warren Maxwell',
        gn => 'Warren',
        sn => 'Maxwell',
        mail => 'warren@example.com',
        userPassword => 'password',
    );
}

set_user_factories('Default');
create_user_in_default: {
    $user = Socialtext::User->new(username=>'warren');
    is $user, undef, 'user does not exist in socialtext';

    $user = Socialtext::User->create(
        email_address => 'warren@example.com',
        username => 'warren maxwell',
        password => 'password',
    );
    isa_ok $user, 'Socialtext::User', 'created a user';
    is $user->homunculus->driver_key, 'Default', 'user in default';
    user_is_unique_to_socialtext('warren maxwell');

    $user_id = $user->user_id;
}

set_user_factories($bar->as_factory, 'Default');
migrate_user_to_ldap: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $bar->as_factory, 'user in bar';
    user_is_unique_to_socialtext('warren maxwell');
}

set_user_factories($foo->as_factory, $bar->as_factory, 'Default');
user_switches_ldap: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $foo->as_factory, 'user in foo';
    user_is_unique_to_socialtext('warren maxwell');
}

$foo->remove('cn=Warren Maxwell,dc=foo,dc=com');
removed_user_migrates: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $bar->as_factory, 'user in bar';
    user_is_unique_to_socialtext('warren maxwell');
}

$bar->remove('cn=Warren Maxwell,dc=bar,dc=com');
cannot_find_user_in_ldap: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->missing, 1, 'user is flagged as missing';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted';
    user_is_unique_to_socialtext('warren maxwell');
}

# User ID lookups need to be treated as a special case, there are no LDAP
# mappings for User ID.

diag "User ID cases";

set_user_factories('Default');
setup_user_id_searches: {
    $foo->add(
        'cn=Milo Toboggan,dc=foo,dc=com',
        objectClass => 'inetOrgPerson',
        cn => 'Milo Toboggan',
        gn => 'Milo',
        sn => 'Toboggan',
        mail => 'milo@example.com',
        userPassword => 'password',
    );
    $bar->add(
        'cn=Milo Toboggan,dc=bar,dc=com',
        objectClass => 'inetOrgPerson',
        cn => 'Milo Toboggan',
        gn => 'Milo',
        sn => 'Toboggan',
        mail => 'milo@example.com',
        userPassword => 'password',
    );

    $user = Socialtext::User->new(username=>'warren');
    is $user, undef, 'user does not exist in socialtext';

    $user = Socialtext::User->create(
        email_address => 'milo@example.com',
        username => 'milo toboggan',
        password => 'password',
    );
    isa_ok $user, 'Socialtext::User', 'created a user';
    is $user->homunculus->driver_key, 'Default', 'user in default';
    user_is_unique_to_socialtext('milo toboggan');

    $user_id = $user->user_id;
}

set_user_factories($bar->as_factory, 'Default');
user_id_in_ldap: {
    $user = Socialtext::User->new(user_id=>$user_id);
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $bar->as_factory, 'user in foo';
    user_is_unique_to_socialtext('milo toboggan');
}

set_user_factories($foo->as_factory, $bar->as_factory, 'Default');
user_id_switches_ldap: {
    $user = Socialtext::User->new(user_id=>$user_id);
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $foo->as_factory, 'user in foo';
    user_is_unique_to_socialtext('milo toboggan');
}

$foo->remove('cn=Milo Toboggan,dc=foo,dc=com');
$bar->remove('cn=Milo Toboggan,dc=bar,dc=com');
user_id_removed_from_ldap: {
    $user = Socialtext::User->new(user_id=>$user_id);
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->missing, 1, 'user is flagged as missing';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted';
    user_is_unique_to_socialtext('milo toboggan');
}


done_testing;
