#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use DateTime::Infinite;
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 8;

use_ok 'Socialtext::User::LDAP';

###############################################################################
### TEST DATA
###############################################################################
my %TEST_USER = (
    user_id         => 123,
    username        => 'cn=First Last,dc=example,dc=com',
    email_address   => 'user@example.com',
    first_name      => 'First',
    last_name       => 'Last',
    driver_name     => 'LDAP:Test LDAP Configuration',
    cached_at       => DateTime::Infinite::Past->new,
);

###############################################################################
# Instantiation with no parameters; should fail
instantiation_no_parameters: {
    my $user = eval { Socialtext::User::LDAP->new() };
    ok !defined $user, 'instantiation, no parameters';
}

###############################################################################
# Do LDAP users have valid passwords?  Yes, always
ldap_users_always_have_valid_passwords: {
    my $user = Socialtext::User::LDAP->new(%TEST_USER);
    isa_ok $user, 'Socialtext::User::LDAP';
    ok $user->has_valid_password(), 'LDAP users -ALWAYS- have valid passwords';
}

###############################################################################
# LDAP users have restricted/hidden passwords
ldap_users_have_restricted_passwords: {
    my $user = Socialtext::User::LDAP->new(%TEST_USER);
    isa_ok $user, 'Socialtext::User::LDAP';
    is $user->password(), '*no-password*', 'LDAP users have restricted passwords';

    $user = Socialtext::User::LDAP->new(%TEST_USER, password => 'sekret');
    isa_ok $user, 'Socialtext::User::LDAP';
    is $user->password(), '*no-password*', 'LDAP users have restricted passwords';
}
