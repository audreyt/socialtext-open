#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Net::LDAP';
use Socialtext::AppConfig;
use Socialtext::LDAP::Config;
use Socialtext::User;

use Test::Socialtext tests => 16;

###############################################################################
###############################################################################
### This test suite looks to make sure that we short-circuit lookups for system
### level user records, so that they go straight to the Default user factory
### instead of iterating through the full list of configured user factories.
###
### Its fairly common to have lots of of these system user lookups, and there
### is no reason we should be firing them off to LDAP servers or other user
### factories when we really know that the *only* place that these users could
### ever live is within the Default store.  Adds overhead from extra LDAP
### requests, which adds latency, which slows down the app.
###############################################################################
###############################################################################

###############################################################################
# FIXTURE:  db
#
# Need the lowest-weight fixture we can get, just so that our configuration
# files and directories are set up for testing and that Pg is running.
fixtures( 'db' );

###############################################################################
# Set up a fake LDAP store
my $ldap_config = Socialtext::LDAP::Config->new(
    id          => 'fake-ldap',
    host        => 'localhost',
    attr_map    => {
        user_id         => 'dn',
        username        => 'mail',
        email_address   => 'mail',
        first_name      => 'givenName',
        last_name       => 'sn',
    },
);
isa_ok $ldap_config, 'Socialtext::LDAP::Config', 'fake LDAP config';
my $rc = Socialtext::LDAP::Config->save($ldap_config);
ok $rc, 'LDAP configuration saved';

END {
    # remove LDAP config when we're done, so we don't pollute other tests
    unlink Socialtext::LDAP::Config->config_filename();
}

###############################################################################
# see the fake LDAP user store to the user_factories
my $factories = 'LDAP:fake-ldap;Default';
my $appconfig = Socialtext::AppConfig->instance();
$appconfig->set( 'user_factories', $factories );
$appconfig->write();
is $appconfig->user_factories(), $factories, 'added LDAP user factory';

###############################################################################
# Look up the "system user" by username; should short-circuit.
system_user_by_username_short_circuits: {
    my $user = Socialtext::User->new(username => 'system-user');
    isa_ok $user, 'Socialtext::User', 'system user record looked up by username';
    isa_ok $user->homunculus, 'Socialtext::User::Default', '... Default homunculus';

    my $mock = Net::LDAP->mocked_object();
    ok !defined $mock, '... and never created an LDAP connection';
}

###############################################################################
# Look up the "system user" by e-mail address; should short-circuit.
system_user_by_email_short_circuits: {
    my $user = Socialtext::User->new(email_address => 'system-user@socialtext.net');
    isa_ok $user, 'Socialtext::User', 'system user record looked up by e-mail address';
    isa_ok $user->homunculus, 'Socialtext::User::Default', '... Default homunculus';

    my $mock = Net::LDAP->mocked_object();
    ok !defined $mock, '... and never created an LDAP connection';
}

###############################################################################
# Look up the "guest user" by username; should short-circuit.
guest_user_by_username_short_circuits: {
    my $user = Socialtext::User->new(username => 'guest');
    isa_ok $user, 'Socialtext::User', 'guest user record looked up by username';
    isa_ok $user->homunculus, 'Socialtext::User::Default', '... Default homunculus';

    my $mock = Net::LDAP->mocked_object();
    ok !defined $mock, '... and never created an LDAP connection';
}

###############################################################################
# Look up the "guest user" by e-mail address; should short-circuit.
guest_user_by_email_short_circuits: {
    my $user = Socialtext::User->new(email_address => 'guest@socialtext.net');
    isa_ok $user, 'Socialtext::User', 'guest user record looked up by e-mail address';
    isa_ok $user->homunculus, 'Socialtext::User::Default', '... Default homunculus';

    my $mock = Net::LDAP->mocked_object();
    ok !defined $mock, '... and never created an LDAP connection';
}

###############################################################################
# Look up any other user; should bounce off of the LDAP factory.
any_other_user_doesnt_short_circuit: {
    my $user = Socialtext::User->new(username => 'any-non-default-user');
    my $mock = Net::LDAP->mocked_object();
    ok defined $mock, '... which created an LDAP connection';
}
