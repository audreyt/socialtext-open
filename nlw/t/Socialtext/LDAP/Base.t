#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 55;
use Socialtext::LDAP::Config;

use_ok 'Socialtext::LDAP::Base';

###############################################################################
### TEST DATA
###############################################################################
our @LDAP_DATA = (
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
our %data = (
    id   => '0deadbeef0',
    name => 'Test LDAP Config',
    base => 'ou=Development,dc=example,dc=com',
    host => '127.0.0.1',
    port => 389,
    follow_referrals => 1,
    attr_map => {
        user_id         => 'dn',
        username        => 'cn',
        email_address   => 'mail',
        first_name      => 'gn',
        last_name       => 'sn',
        },
);
our $config = Socialtext::LDAP::Config->new(%data);

###############################################################################
# Instantiation with no config; should fail
instantiation_no_config: {
    my $ldap = Socialtext::LDAP::Base->new();
    ok !defined $ldap, 'instantiation, no config';
}

###############################################################################
# Instantiation with failed connection; should fail
instantiation_fail_to_ldap_connect: {
    Net::LDAP->set_mock_behaviour(
        connect_fail => 1,
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    ok !defined $ldap, 'fail to LDAP connect';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to connect/, '... logged connection failure';
}

###############################################################################
# Instantiation ok
instantiation_ok: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    is $mock->{sources}, $config->host(), 'connected with right host';
    is $mock->{port}, $config->port(), 'connected with right port';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Instantiation; multiple hosts
instantiation_multiple_hosts_ok: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $hosts  = ['127.0.0.1', '192.168.2.1'];
    my $config = Socialtext::LDAP::Config->new(%data);
    $config->host( $hosts );

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    is_deeply $mock->{sources}, $hosts, 'connected with multiple hosts';
    is $mock->{port}, $config->port(), 'connected with right port';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Instantiation; LDAP URL, not IP
instantiation_ldap_url_ok: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $config = Socialtext::LDAP::Config->new(%data);
    $config->host( 'ldaps://127.0.0.1:636' );

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    is $mock->{sources}, $config->host(), 'connected with correct host';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Bind failure
bind_failure: {
    Net::LDAP->set_mock_behaviour(
        bind_fail => 1,
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok !$ldap->bind(), 'bind failure';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to bind/, '... logged bind failure';
}

###############################################################################
# Bind requires authentication, none provided; should fail
bind_requires_auth: {
    Net::LDAP->set_mock_behaviour(
        bind_credentials => {
            'requires' => 'authentication',
            },
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok !$ldap->bind(), 'bind requires authentication';

    # VERIFY LOGS; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to bind/, '... logged bind failure';
}

###############################################################################
# Anonymous bind ok
bind_anonymous_ok: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok $ldap->bind(), 'anonymous bind';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    my ($self, $dn, %opts) = $mock->call_args(1);
    ok !$dn, '... empty bind dn (anonymous)';
    ok !$opts{password}, '... empty bind password (anonymous)';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Authenticated bind ok
bind_authenticated_ok: {
    my $bind_user = 'cn=Manager,dc=example,dc=com';
    my $bind_pass = 'abc123';
    Net::LDAP->set_mock_behaviour(
        bind_credentials => {
            $bind_user => $bind_pass,
            },
        );
    clear_log();

    my $config = Socialtext::LDAP::Config->new(%data);
    $config->bind_user($bind_user);
    $config->bind_password($bind_pass);

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok $ldap->bind(), 'authenticated bind';

    # VERIFY mocks
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    my ($self, $dn, %opts) = $mock->call_args(1);
    is $dn, $config->bind_user(), '... correct bind dn';
    is $opts{password}, $config->bind_password(), '... correct bind password';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Authentication failure
authentication_failure: {
    Net::LDAP->set_mock_behaviour(
        bind_fail => 1,
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok !$ldap->authenticate('foo','bar'), 'authentication failure';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'info', qr/authentication failed/, '... auth failed';
}

###############################################################################
# Authentication success
#
# NOTE: w/follow_referrals on, authentication does a search first to find the
# user record and make sure we're speaking to the right LDAP server; make sure
# that we've got a test user around to return.
authentication_success: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ $LDAP_DATA[0] ],
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok $ldap->authenticate('foo','bar'), 'authentication success';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Authentication allows missing username/password (anonymous auth)
authentication_anonymous_ok: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    ok $ldap->authenticate(), 'anonymous authentication success';

    # VERIFY logs; should be empty
    is logged_count(), 0, '... logged right number of entries';
}

###############################################################################
# Search failure
search_failure: {
    Net::LDAP->set_mock_behaviour(
        search_fail => 1,
        search_results => [ @LDAP_DATA ],
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';
    ok $ldap->bind();

    my $mesg = $ldap->search();
    isa_ok $mesg, 'Net::LDAP::Search';
    ok $mesg->code(), 'search failed';
}

###############################################################################
# Search success
search_success: {
    Net::LDAP->set_mock_behaviour(
        search_results => [ @LDAP_DATA ],
        );
    clear_log();

    my $ldap = Socialtext::LDAP::Base->new($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base';
    ok $ldap->bind();

    my $mesg = $ldap->search();
    isa_ok $mesg, 'Net::LDAP::Search';
    ok !$mesg->code(), 'search success';
    is $mesg->count(), 2, '... correct number of search results';
}
