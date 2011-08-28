#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User;
use Socialtext::User::LDAP::Factory;
use Socialtext::LDAP::Operations;

fixtures('db');

$Socialtext::LDAP::CacheEnabled = 0;
$Socialtext::User::Cache::Enabled = 0;
$Socialtext::User::LDAP::Factory::CacheEnabled = 0;

my ($one,$two); # LDAP stores.
my $one_dn = 'cn=Warren Maxwell,ou=people,dc=foo,dc=com';
my $two_dn = 'cn=Warren Maxwell,ou=terminated,dc=foo,dc=com';
my $user; # test user

setup: { # same user 2x, but with different dn's in different LDAPs.
    $one = initialize_ldap('foo');
    $one->add(
        'ou=people,dc=foo,dc=com',
        objectClass => 'organizationalUnit',
        description => ' current employees',
        ou => 'people',
    );
    $one->add(
        $one_dn,
        objectClass => 'inetOrgPerson',
        cn => 'Warren Maxwell',
        ou => 'people',
        gn => 'Warren',
        sn => 'Maxwell',
        mail => 'warren@example.com',
        userPassword => 'password',
    );

    $two = initialize_ldap('foo');
    $two->add(
        'ou=terminated,dc=foo,dc=com',
        objectClass => 'organizationalUnit',
        description => ' current employees',
        ou => 'terminated',
    );
    $two->add(
        $two_dn,
        objectClass => 'inetOrgPerson',
        cn => 'Warren Maxwell',
        ou => 'terminated',
        gn => 'Warren',
        sn => 'Maxwell',
        mail => 'warren@example.com',
        userPassword => 'password',
    );
}

set_user_factories($two->as_factory, 'Default');
vivify_user: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'vivified user';
    is $user->homunculus->driver_key, $two->as_factory, 'user has factory';
    is $user->driver_unique_id, $two_dn, 'user has dn';
}

simple_refresh: {
    Socialtext::LDAP::Operations->RefreshUsers();
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'freshened user';
    is $user->homunculus->driver_key, $two->as_factory, 'user has factory';
    is $user->driver_unique_id, $two_dn, 'user has dn';
}

set_user_factories($one->as_factory, $two->as_factory, 'Default');
refresh_with_updated_ldap: {
    Socialtext::LDAP::Operations->RefreshUsers();
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'freshened user with new ldap';
    is $user->homunculus->driver_key, $one->as_factory, 'user has factory';
    is $user->driver_unique_id, $one_dn, 'user has dn';
    user_is_unique_to_socialtext('warren maxwell');
}

done_testing;
