#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 10;

# FIXTURE:  ldap_anonymous
#
# These tests specifically require that we're using an anonymous LDAP
# connection.
fixtures( 'ldap_anonymous' );
use_ok 'Socialtext::User::LDAP::Factory';

###############################################################################
### TEST DATA
###############################################################################
my @TEST_USERS = (
    { dn            => 'cn=First Last,dc=example,dc=com',
      cn            => 'First Last',
      authPassword  => 'abc123',
      gn            => 'First',
      sn            => 'Last',
      mail          => 'user@example.com',
    },
    { dn            => 'cn=Another User,dc=example,dc=com',
      cn            => 'Another User',
      authPassword  => 'def987',
      gn            => 'Another',
      sn            => 'User',
      mail          => 'user@example.com',
    },
);

###############################################################################
# LDAP "anonymous bind" is supported
ldap_anonymous_bind: {
    # Flush the LDAP Connection Cache
    Socialtext::LDAP->ConnectionCache->clear();

    # Set up our mocked LDAP connection
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );
    clear_log();

    # Connect to LDAP and create an LDAP User Factory
    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory', 'created factory ok';
    ok $factory->connect(), 'was able to connect to the server';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    my ($self, $dn, %opts) = $mock->call_args(1);
    ok !defined $dn, 'anonymous bind; no username';
    ok !exists $opts{'password'}, 'anonymous bind; no password';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Instantiation with missing authentication returns empty handed.
instantiation_bind_requires_additional_auth: {
    # Flush the LDAP Connection Cache
    Socialtext::LDAP->ConnectionCache->clear();

    # Set up our mocked LDAP connection
    Net::LDAP->set_mock_behaviour(
        bind_credentials => {
            'requires' => 'authentication',
            },
        );
    clear_log();

    # Connect to LDAP and create an LDAP User Factory
    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory', 'created factory ok';
    ok !$factory->connect(),'instantiation w/bind requires additional auth';

    # VERIFY logs; make sure we failed for the right reason
    logged_like 'error', qr/unable to bind/, '... logged bind failure';
}
