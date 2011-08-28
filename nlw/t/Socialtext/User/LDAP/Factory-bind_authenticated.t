#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 7;

# FIXTURE:  ldap_authenticated
#
# These tests specificially require that we're using an -authenticated- LDAP
# connection.
fixtures( 'ldap_authenticated' );
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
# LDAP "authenticated bind" is supported
ldap_authenticated_bind: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        bind_credentials => {
            # matches credentials in 'ldap_authenticated' fixture
            'cn=First Last,dc=example,dc=com' => 'abc123',
            },
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory', 'authenticated bind...';
    ok $factory->connect, '... was able to connect';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    my ($self, $dn, %opts) = $mock->call_args(1);
    ok defined $dn, 'bind has correct username';
    ok exists $opts{'password'}, 'bind has correct password';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... log is empty';
}
