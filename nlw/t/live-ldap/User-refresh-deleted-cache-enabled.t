#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Socialtext;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Socialtext::User;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::User::Factory;

fixtures('db');

my $dn = 'cn=Warren Maxwell,dc=foo,dc=com';
my $ldap = initialize_ldap('foo');
$ldap->add(
    $dn,
    objectClass => 'inetOrgPerson',
    cn => 'Warren Maxwell',
    gn => 'Warren',
    sn => 'Maxwell',
    mail => 'warren@foo.com'
);

my $user = Socialtext::User->new(email_address=>'warren@foo.com');
ok $user, 'instantiated an LDAP user';
my $id = $user->user_id;
Socialtext::User::Factory->ExpireUserRecord(user_id=>$id);

diag "sleep one second to ensure user is expired";
sleep 1;

$user = Socialtext::User->new(user_id=>$id);
isa_ok $user->homunculus, 'Socialtext::User::LDAP', 'user is LDAP';

Socialtext::User::Factory->ExpireUserRecord(user_id=>$id);
sql_execute('UPDATE all_users SET is_deleted = true WHERE user_id = ?', $id);


diag "sleep one second to ensure user is expired";
sleep 1;

$user = Socialtext::User->new(user_id=>$id);
isa_ok $user->homunculus, 'Socialtext::User::Deleted', 'user is deleted';


done_testing;
