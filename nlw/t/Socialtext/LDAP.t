#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 58;
use Test::MockObject::Extends;

use_ok 'Socialtext::LDAP';

###############################################################################
### TEST DATA
###############################################################################
our %data = (
    id   => 'deadbeef',
    name => 'Test LDAP Connection',
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

###############################################################################
# We're going to do some low-level testing here, turn off the LDAP connection
# cache.
###############################################################################
{
    no warnings 'once';
    $Socialtext::LDAP::CacheEnabled = 0;
}

###############################################################################
# When we're done, *CLEAR/EMPTY* the LDAP configuration; we're going to monkey
# around with it here in this test and don't want to pollute other LDAP tests.
###############################################################################
END {
    Socialtext::LDAP::Config->save();
}

###############################################################################
# List available LDAP connections (when only one exists)
available_ldap_connections_one: {
    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # get the list of available LDAP configurations
    my @available = Socialtext::LDAP->available();
    ok @available, 'got list of available LDAP connections';
    is scalar @available, 1, '... contains a single connection';
    is $available[0], $config->id, '... ... and its the right one';
}

###############################################################################
# List available LDAP connections (when more than one exist)
available_ldap_connections_more_than_one: {
    # create the LDAP configuration file
    my $first = Socialtext::LDAP::Config->new(%data);
    $first->id( Socialtext::LDAP::Config->generate_driver_id() );

    my $second = Socialtext::LDAP::Config->new(%data);
    $second->id( Socialtext::LDAP::Config->generate_driver_id() );

    Socialtext::LDAP::Config->save($first, $second);

    # get the list of available LDAP configurations
    my @available = Socialtext::LDAP->available();
    ok @available, 'got list of available LDAP connections';
    is scalar @available, 2, '... contains right number of connections';
    is $available[0], $first->id, '... ... first one was first';
    is $available[1], $second->id, '... ... second one was second';
}

###############################################################################
# Get default configuration
get_configuration_default: {
    # create the LDAP configuration file
    my $first = Socialtext::LDAP::Config->new(%data);
    $first->name('First LDAP Config');

    my $second = Socialtext::LDAP::Config->new(%data);
    $second->name('Second LDAP Config');

    Socialtext::LDAP::Config->save($first, $second);

    # get the default configuration
    my $config = Socialtext::LDAP->default_config();
    isa_ok $config, 'Socialtext::LDAP::Config', 'retrieved default config';
    is_deeply $config, $first, '... and its the FIRST config in the file';
}

###############################################################################
# Get configuration by driver id.
get_configuration_by_id: {
    # create the LDAP configuration file
    my $first = Socialtext::LDAP::Config->new(%data);
    $first->id( Socialtext::LDAP::Config->generate_driver_id() );

    my $second = Socialtext::LDAP::Config->new(%data);
    my $driver_id = Socialtext::LDAP::Config->generate_driver_id();
    $second->id( $driver_id );

    Socialtext::LDAP::Config->save($first, $second);

    # get the named configuration
    my $config = Socialtext::LDAP->config($driver_id);
    isa_ok $config, 'Socialtext::LDAP::Config', 'retrieved named config';
    is_deeply $config, $second, '... and its the correct config';
}

###############################################################################
# Get unknown configuration; should return empty handed.
get_configuration_unknown: {
    # create the LDAP configuration file
    my $first = Socialtext::LDAP::Config->new(%data);
    $first->id( Socialtext::LDAP::Config->generate_driver_id() );

    my $second = Socialtext::LDAP::Config->new(%data);
    $second->id( Socialtext::LDAP::Config->generate_driver_id() );

    Socialtext::LDAP::Config->save($first, $second);

    # get the named configuration
    my $config = Socialtext::LDAP->config('this-is-not-a-known-driver-id');
    ok !$config, 'unknown named configuration';
}

###############################################################################
# Connect w/unknown LDAP back-end; fails to load
connect_failure_unknown_backend: {
    my $config = Socialtext::LDAP::Config->new(%data);
    $config->backend('Foo');
    clear_log();

    my $ldap = Socialtext::LDAP->connect($config);
    ok !$ldap, 'connect failure; unknown LDAP back-end';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to load.*Foo/, '... unable to load Foo back-end';
}

###############################################################################
# Connect w/invalid config; fails to instantiate
connect_failure_to_instantiate_backend: {
    my $config = Socialtext::LDAP::Config->new(%data);
    $config->backend('Foo');
    clear_log();

    local %INC = %INC;
    $INC{'Socialtext/LDAP/Foo.pm'} = 1;

    my $ldap = Socialtext::LDAP->connect($config);
    ok! $ldap, 'connect failure; unable to instantiate LDAP back-end';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to instantiate.*Foo/, '... unable to instantiate Foo back-end';
}

###############################################################################
# Connect, default back-end
connect_default_backend: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    my $config = Socialtext::LDAP::Config->new(%data);

    my $ldap = Socialtext::LDAP->connect($config);
    isa_ok $ldap, 'Socialtext::LDAP::Base', 'used default back-end';

    # VERIFY mocks; want to make sure connection is bound
    my $mock = Net::LDAP->mocked_object();
    $mock->called_ok( 'bind' );
}

###############################################################################
# Connect, explicit back-end
connect_explicit_backend: {
    Net::LDAP->set_mock_behaviour();
    
    my $config = Socialtext::LDAP::Config->new(%data);
    $config->backend('OpenLDAP');

    my $ldap = Socialtext::LDAP->connect($config);
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'used OpenLDAP back-end';

    # VERIFY mocks; want to make sure connection is bound
    my $mock = Net::LDAP->mocked_object();
    $mock->called_ok( 'bind' );
}

###############################################################################
# Instantiation; failure to read configuration
instantiation_failure_to_read_config: {
    # remove any existing configuration file
    my $filename = Socialtext::LDAP::Config->config_filename();
    unlink $filename;
    ok !-e $filename, 'config file not there any more';

    # attempt to connect
    my $ldap = Socialtext::LDAP->new();
    ok !$ldap, 'failed to instantiate; failed to read config';
}

###############################################################################
# Instantiation; connection failure
instantiation_connection_failure: {
    Net::LDAP->set_mock_behaviour(
        connect_fail => 1,
        );
    clear_log();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to connect
    my $ldap = Socialtext::LDAP->new();
    ok !$ldap, 'failed to instantiate; connection failure';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to connect/, '... unable to connect';
}

###############################################################################
# Instantiation; bind failure
instantiation_bind_failure: {
    Net::LDAP->set_mock_behaviour(
        bind_fail => 1,
        );
    clear_log();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to connect
    my $ldap = Socialtext::LDAP->new();
    ok !$ldap, 'failed to instantiate; bind failure';

    # VERIFY logs; make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of entries';
    next_log_like 'error', qr/unable to bind/, '... unable to bind';
}

###############################################################################
# Instantiation
instantiation: {
    Net::LDAP->set_mock_behaviour();
    clear_log();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to connect
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::Base';

    # VERIFY mocks; want to make sure connection is bound
    my $mock = Net::LDAP->mocked_object();
    $mock->called_ok( 'bind' );
}

###############################################################################
# Authentication; failure to read config
authentication_failure_to_read_config: {
    # remove any existing configuration file
    my $filename = Socialtext::LDAP::Config->config_filename();
    unlink $filename;
    ok !-e $filename, 'config file not there any more';

    # attempt to authenticate
    my %opts = (
        user_id  => 'myDn',
        password => 'myPassword',
    );
    my $auth_ok = Socialtext::LDAP->authenticate(%opts);
    ok !$auth_ok, 'auth; failed to read config';
}

###############################################################################
# Authentication; failure to connect
authentication_failure_to_connect: {
    Net::LDAP->set_mock_behaviour(
        connect_fail => 1,
        );
    clear_log();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to authenticate
    my %opts = (
        user_id  => 'myDn',
        password => 'myPassword',
    );
    my $auth_ok = Socialtext::LDAP->authenticate(%opts);
    ok! $auth_ok, 'auth; failed to connect';

    # VERIFY logs; want to make sure we failed for the right reason
    is logged_count(), 1, '... logged right number of reasons';
    next_log_like 'error', qr/unable to connect/, '... failed to connect';
}

###############################################################################
# Authentication; auth failure (bad password)
authentication_failure: {
    my $bind_user = 'myDn';
    my $bind_password = 'myPassword';
    Net::LDAP->set_mock_behaviour(
        bind_credentials => {
            anonymous  => 1,
            $bind_user => $bind_password,
            },
        search_results => [ { dummy => 'user' } ],
        );
    clear_log();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to authenticate
    my %opts = (
        user_id  => $bind_user,
        password => 'this-is-the-wrong-password',
    );
    my $auth_ok = Socialtext::LDAP->authenticate(%opts);
    ok! $auth_ok, 'auth; failed to authenticate';

    # VERIFY logs; want to make sure we failed for the right reason, and on
    # the right bind
    is logged_count(), 1, '... logged right number of reasons';
    next_log_like 'info', qr/authentication failed/, '... auth failure';

    my $mock = Net::LDAP->mocked_object();
    my ($self, $dn, %args);

    $mock->called_pos_ok( 1, 'bind' );
    ($self, $dn, %args) = $mock->call_args(1);
    ok !$dn, '... initial bind anonymous';

    $mock->called_pos_ok( 2, 'search' );

    $mock->called_pos_ok( 3, 'bind' );
    ($self, $dn, %args) = $mock->call_args(3);
    is $dn, $opts{user_id}, '... correct bind dn for authentication';
    is $args{password}, $opts{password}, '... correct bind password for authentication';
}

###############################################################################
# Authentication success
authentication_success: {
    my $bind_user = 'myDn';
    my $bind_pass = 'myPassword';
    Net::LDAP->set_mock_behaviour(
        bind_credentials => {
            anonymous  => 1,
            $bind_user => $bind_pass,
            },
        search_results => [ { dummy => 'user' } ],
        );

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to authenticate
    my %opts = (
        user_id  => $bind_user,
        password => $bind_pass,
    );
    my $auth_ok = Socialtext::LDAP->authenticate(%opts);
    ok $auth_ok, 'authentication success';

    # VERIFY logs; bind anonymously, then search for user, then bind
    # w/user+pass
    my $mock = Net::LDAP->mocked_object();
    my ($self, $dn, %args);

    $mock->called_pos_ok( 1, 'bind' );
    ($self, $dn, %args) = $mock->call_args(1);
    ok !$dn, '... initial bind anonymous';

    $mock->called_pos_ok( 2, 'search' );

    $mock->called_pos_ok( 3, 'bind' );
    ($self, $dn, %args) = $mock->call_args(3);
    is $dn, $opts{user_id}, '... correct bind dn for authentication';
    is $args{password}, $opts{password}, '... correct bind password for authentication';
}

###############################################################################
# Authentication success (anonymous)
authentication_anonymous_success: {
    Net::LDAP->set_mock_behaviour();

    # create the LDAP configuration file
    my $config = Socialtext::LDAP::Config->new(%data);
    Socialtext::LDAP::Config->save($config);

    # attempt to authenticate
    my $auth_ok = Socialtext::LDAP->authenticate();
    ok $auth_ok, 'authentication (anonymous) success';

    # VERIFY logs; want to make sure the bind was done anonymously
    my $mock = Net::LDAP->mocked_object();
    $mock->called_pos_ok( 1, 'bind' );
    my ($self, $dn, %args) = $mock->call_args(1);
    ok !$dn, '... empty bind dn (anonymous)';
    ok !$args{password}, '... empty bind password (anonymous)';
}
