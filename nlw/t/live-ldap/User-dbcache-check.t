#!/usr/bin/env perl
use strict;
use warnings;

use mocked 'Socialtext::Log', qw(:tests st_log);
use Test::More;
use Test::Socialtext;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::SQL qw(sql_execute);
use Socialtext::User;
use Socialtext::User::LDAP::Factory;

fixtures(qw(db no-ceq-jobs));

$Socialtext::LDAP::CacheEnabled = 1;
$Socialtext::User::Cache::Enabled = 0;
$Socialtext::User::LDAP::Factory::CacheEnabled = 1;

my ($foo,$bar); # LDAP stores.
my $user = Socialtext::User->create(
    username => 'warren maxwell',
    email_address => 'warren@example.com',
    password => 'password',
);
my $user_id = $user->user_id;
my $username = $user->username;

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
}

set_user_factories('Default');

simeple_cache_hit: {
    diag "simple_cache_hit:";
    make_user_fresh($user_id);
    clear_log();

    my $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::Default';
    my $log = dump_log();
    like $log, qr/Returned cached user/, 'cache hit';
}

simple_cache_miss: {
    diag "simple_cache_miss:";
    make_user_stale($user_id);
    clear_log();

    my $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::Default';
    my $log = dump_log();
    unlike $log, qr/Returned cached user/, 'cache miss';

    clear_log();

    my $freshened = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::Default';
    $log = dump_log();
    like $log, qr/Returned cached user/, 'cache hit';
}

# Enable LDAP lookups
set_user_factories($foo->as_factory, 'Default');

fresh_default_user_avoids_ldap: {
    diag "fresh_default_user_avoids_ldap:";
    make_user_fresh($user_id);
    clear_log();

    $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::Default';
    my $log = dump_log();
    like $log, qr/Returned cached user/, 'cache hit';
}

stale_default_user_updates_to_LDAP: {
    diag "stale_default_user_updates_to_LDAP:";
    make_user_stale($user_id);
    clear_log();

    $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::LDAP';
    my $log = dump_log();

    # be specific about the cache miss here: as a part of the update process,
    # we look up all of the user's relations, which generates cache hits
    # searching for user_id's.
    unlike $log, qr/Returned cached user, username => $username/, 'cache miss';
    like $log, qr/found user in LDAP search/, 'LDAP hit';
}

fresh_LDAP_user_avoids_LDAP: {
    diag "fresh_ldap_user_avoids_LDAP:";
    make_user_fresh($user_id);
    clear_log();

    $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::LDAP';
    my $log = dump_log();
    like $log, qr/Returned cached user/, 'cache hit';
}

done_testing;
exit;
################################################################################

sub make_user_fresh {
    my $user_id = shift;
    sql_execute(qq{
        UPDATE all_users
           SET cached_at = 'infinity'::timestamptz
         WHERE user_id = ?
    }, $user_id);
}

sub make_user_stale {
    my $user_id = shift;
    sql_execute(qq{
        UPDATE all_users
           SET cached_at = '-infinity'::timestamptz
         WHERE user_id = ?
    }, $user_id);
}
