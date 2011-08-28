#!/user/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Socialtext::User;
use Socialtext::SQL qw/sql_execute/;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User::LDAP::Factory;

fixtures('db');

$Socialtext::LDAP::CacheEnabled = 0;
$Socialtext::User::Cache::Enabled = 0;
$Socialtext::User::LDAP::Factory::CacheEnabled = 0;

my ($foo, $bar);
my ($user, $deleted_id);

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

set_user_factories($bar->as_factory, 'Default');
vivify_user_in_ldap: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    is $user->homunculus->driver_key, $bar->as_factory, 'user in bar';
    isa_ok $user->homunculus, 'Socialtext::User::LDAP';
}

flag_user_as_deleted: {
    sql_execute(qq{
        UPDATE all_users SET is_deleted = true WHERE user_id = ?
    }, $user->user_id);
    my $proto = Socialtext::User->GetProtoUser(username=>'warren maxwell');
    is $proto, undef, 'no user found after flagging deleted';
}

revivify_user_returns_deleted: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted';
}

set_user_factories($foo->as_factory, $bar->as_factory, 'Default');
user_in_new_factory_is_still_deleted: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted';
}

set_user_factories($bar->as_factory, $foo->as_factory, 'Default');
refreshing_user: {
    $user = Socialtext::User->new(username=>'warren maxwell');
    isa_ok $user, 'Socialtext::User', 'found a user';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted';
}

done_testing;
