#!/user/bin/perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 5;
use Socialtext::Group;
use Socialtext::Group::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;

fixtures('db');

local $Socialtext::Group::Factory::Asynchronous = 0;

my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn for ldap';
ok $ldap->add_ldif('t/test-data/ldap/groups-nested.ldif'), '... groups';

my $humans_dn = 'cn=Humans,DC=example,DC=com';
my $othe_dn = 'cn=Oh\, the humanity!,dc=example,dc=com';

simple_nesting: {
    my $humans = Socialtext::Group->GetGroup({driver_unique_id => $humans_dn});
    my $users = $humans->users;
    is $users->count, 2, "correct user-count";
    my @users = sort { $a->email_address cmp $b->email_address }
        $humans->users->all;
    is $users[0]->email_address, 'janesmith@example.com';
    is $users[1]->email_address, 'johnsmith@example.com';
}
