#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 26;

# FIXTURE:  ldap_*
#
# These tests have no specific requirement as to whether we're using an
# anonymous or authenticated LDAP connection.
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
# Search; empty search should return empty handed
search_empty_should_return_empty_handed: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ @TEST_USERS ],
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my @users = $factory->Search();
    is scalar(@users), 0, 'search w/empty terms should be empty handed';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Search; no results
search_no_results: {
    Net::LDAP->set_mock_behaviour(
        search_results => [],
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my @users = $factory->Search('foo');
    is scalar(@users), 0, 'search w/no results has correct number of results';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Search; single result
search_single_result: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my @users = $factory->Search('foo');
    is scalar(@users), 1, 'search w/single result has correct number of results';
}

###############################################################################
# Search; multiple results
search_multiple_results: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ @TEST_USERS ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my @users = $factory->Search('foo');
    is scalar(@users), 2, 'search w/multiple results has correct number of results';
}

###############################################################################
# Search; internal sanity checks
search_sanity_checks: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ @TEST_USERS ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my @users = $factory->Search('foo');
    is scalar(@users), 2;

    # check format/content of results
    my $user = $users[0];
    isa_ok $user, 'HASH', 'search results are plain hash-refs';
    is scalar(keys(%{$user})), 3, 'search results have right # of keys';
    is $user->{'driver_name'}, $factory->driver_key(), 'result key: driver_name';
    is $user->{'email_address'}, 'user@example.com', 'result key: email_address';
    is $user->{'name_and_email'}, 'First Last <user@example.com>', 'result key: name_and_email';

    # VERIFY mocks...
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    $mock->called_pos_ok( 2, 'search' );
    my ($self, %opts) = $mock->call_args(2);
    is $opts{'scope'}, 'sub', 'sub-tree search';
    like $opts{'filter'}, qr/\(cn=\*foo\*\)/,   'search includes cn';
    like $opts{'filter'}, qr/\(mail=\*foo\*\)/, 'search includes mail';
    like $opts{'filter'}, qr/\(gn=\*foo\*\)/,   'search includes gn';
    like $opts{'filter'}, qr/\(sn=\*foo\*\)/,   'search includes sn';
    like $opts{'filter'}, qr/^\(\|/,            'search is OR-based';
}
