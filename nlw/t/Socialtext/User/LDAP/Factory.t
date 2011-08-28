#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::More;
use Test::Socialtext;
use Test::Socialtext::User;

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
# Factory instantiation with no parameters; should pick up some sort of LDAP
# connection (we don't dictate which, so we're not going to presume which one
# it is; we'll leave that to the testing in ST::LDAP).
instantiation_no_parameters: {
    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';
    # make sure it has a name, but don't care which one it is
    like $factory->driver_key, qr/^LDAP:.+/, '... driver has a name';
}

###############################################################################
# Factory instantiation with named LDAP connection; should use specified LDAP
# connection.
instantiation_named_ldap_connection: {
    my $factory = Socialtext::User::LDAP::Factory->new('1deadbeef1');
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';
    is $factory->driver_key, 'LDAP:1deadbeef1', '... driver name: LDAP:1deadbeef1';
}

###############################################################################
# Instantiation with failed connection; should fail
instantiation_fail_to_ldap_connect: {
    Net::LDAP->set_mock_behaviour(
        connect_fail    => 1,
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    ok $factory, "got the object just fine";
    ok !$factory->connect, "connection fails";

    # VERIFY logs; make sure we failed for the right reason
    logged_like 'error', qr/unable to connect/, '... logged connection failure';
}

###############################################################################
# Instantiation when unable to bind; returns empty handed
instantiation_bind_failure: {
    Net::LDAP->set_mock_behaviour(
        bind_fail => 1,
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    ok $factory, "got the object just fine";
    ok !$factory->connect, "connection fails";

    # VERIFY logs; make sure we failed for the right reason
    logged_like 'error', qr/unable to bind/, '... logged bind failure';
}

###############################################################################
# Verify that we can connect to LDAP.
simple_connection_ok: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
    );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    ok $factory, "got the object just fine";
    ok $factory->connect, "connection succeeds!";

    is logged_count(), 0, "nothing logged";
}

###############################################################################
# Verify list of valid search terms when retrieving a user record.
get_user_valid_search_terms: {
    my $guard = Test::Socialtext::User->snapshot();
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
    );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    # "username" is valid search term
    my $user = $factory->GetUser(username=>'First Last');
    isa_ok $user, 'Socialtext::User::LDAP', 'username; valid search term';

    # "user_id" is a valid search term (but only if User is already in the DB)
    $user = $factory->GetUser(user_id => $user->user_id);
    isa_ok $user, 'Socialtext::User::LDAP', 'user_id; valid search term';
    # ... clear the long-term cache
    Test::Socialtext::User->delete_recklessly($user);

    # "driver_unique_id" is valid search term
    my $dn = 'cn=First Last, dc=example,dc=com';
    $user = $factory->GetUser(driver_unique_id => $dn);
    isa_ok $user, 'Socialtext::User::LDAP',
        'driver_unique_id; valid search term';
    # ... clear the long-term cache
    Test::Socialtext::User->delete_recklessly($user);

    # "email_address" is valid search term
    $user = $factory->GetUser(email_address=>'user@example.com');
    isa_ok $user, 'Socialtext::User::LDAP', 'email_address; valid search term';

    no_warnings_logged_ok "no warnings logged to this point", qr/Can't connect to pushd/;

    # "first_name" is mapped, but is -NOT- a valid search term
    my $missing_user = $factory->GetUser(first_name=>'First');
    ok !defined $missing_user, 'first_name; INVALID search term';

    # "cn" isn't a valid search term
    $missing_user = $factory->GetUser(cn=>'First Last');
    ok !defined $missing_user, 'cn; INVALID search term';
}

###############################################################################
# Verify that retrieving a user record with blank/undefined value returns
# empty handed.
get_user_blank_values: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(username=>undef);
    ok !defined $user, 'get user w/undef value returns empty-handed';
}

###############################################################################
# Verify that retrieving a user record which fails to find a match in LDAP
# returns empty handed.
get_user_unknown_user: {
    Net::LDAP->set_mock_behaviour(
        search_results => [],
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(username=>'First Last');
    ok !defined $user, 'get user w/o user in LDAP returns empty-handed';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'debug', qr/unable to find user/, '... logged inability to find user';
}

###############################################################################
# Retrieving a user record with multiple matches should fail; how do we know
# which one to choose?
get_user_multiple_matches: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ @TEST_USERS ],
        );
    clear_log();

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = eval { $factory->GetUser(email_address=>'user@example.com') };
    my $e = $@;
    like $e, qr/found multiple matches/, '... died finding multiple matches';
    ok !defined $user, 'get user w/multiple matches should fail';
}

###############################################################################
# User retrieval via "username" is done as a sub-tree search
get_user_via_username_is_subtree: {
    my $guard = Test::Socialtext::User->snapshot();
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(username=>'First Last');
    isa_ok $user, 'Socialtext::User::LDAP';

    # VERIFY mocks...
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    $mock->called_pos_ok( 2, 'search' );
    my ($self, %opts) = $mock->call_args(2);
    is $opts{'scope'}, 'sub', 'username search is sub-tree';
}

###############################################################################
# User retrieval via "email_address" is done as a sub-tree search
get_user_via_email_address_is_subtree: {
    my $guard = Test::Socialtext::User->snapshot();
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(email_address=>'user@example.com');
    isa_ok $user, 'Socialtext::User::LDAP';

    # VERIFY mocks...
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    $mock->called_pos_ok( 2, 'search' );
    my ($self, %opts) = $mock->call_args(2);
    is $opts{'scope'}, 'sub', 'email_address search is sub-tree';
}

###############################################################################
# User retrieval via "driver_unique_id" is optimized to be done as an exact
# search IFF driver_unique_id is a subtree of the base.
get_user_via_driver_unique_id_base_mismatch: {
    my $guard = Test::Socialtext::User->snapshot();
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
        );
    my $dn = 'cn=First Last,dc=example,dc=com';

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(driver_unique_id=>$dn);
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    $mock->called_pos_ok( 2, 'search' );
    my ($self, %opts) = $mock->call_args(2);
    is $opts{'scope'}, 'sub', 'subtree search when id is not in base';
    is $opts{'base'}, 'dc=foo,dc=bar', 'default base when id is not in base';
}

get_user_via_driver_unique_id_base_match: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $TEST_USERS[0] ],
    );
    my $dn = 'cn=something,dc=foo,dc=bar';

    my $factory = Socialtext::User::LDAP::Factory->new();
    isa_ok $factory, 'Socialtext::User::LDAP::Factory';

    my $user = $factory->GetUser(driver_unique_id=>$dn);
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    $mock->called_pos_ok( 2, 'search' );
    my ($self, %opts) = $mock->call_args(2);
    is $opts{'scope'}, 'base', 'base search when id is in base';
    is $opts{'base'}, $dn, 'base is exact search';
}

done_testing;
