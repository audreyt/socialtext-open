#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Socialtext::LDAP;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 45;

use_ok 'Socialtext::LDAP::OpenLDAP';

###############################################################################
# Fixtures: db
#
# Need the database running, but don't care what's in it.
fixtures( 'db' );

###############################################################################
# We're going to do some low-level testing here, turn off the LDAP connection
# cache.
###############################################################################
{
    no warnings 'once';
    $Socialtext::LDAP::CacheEnabled = 0;
}

###############################################################################
# Instantiation; connecting to a live OpenLDAP server.
instantiation_ok: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # try to connect
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'connected to OpenLDAP server';
}

###############################################################################
# Instantiation; failure to bind due to invalid credentials.
instantiation_invalid_credentials: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # set incorrect password into config, and save LDAP config to YAML
    my $config = $openldap->ldap_config();
    $config->bind_password( 'this-is-the-wrong-password' );
    ok $openldap->add_to_ldap_config(), 'saved custom LDAP config to YAML';

    # try to connect; should fail
    clear_log();
    my $ldap = Socialtext::LDAP->new();
    ok !$ldap, 'failed to connect to LDAP server';
    logged_like 'error', qr/unable to bind/, '... failed to bind';
}

###############################################################################
# Instantiation; requires auth (anonymous bind not allowed)
instantiation_requires_auth: {
    # bootstrap OpenLDAP and save the config out to YAML
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new(requires_auth=>1);
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # connect, to make sure that it works fine with required auth
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'connect fine with auth';
    $ldap = undef;

    # remove user/pass from config, so we do an anonymous bind.
    $openldap->ldap_config->bind_user( undef );
    $openldap->ldap_config->bind_password( undef );
    ok $openldap->add_to_ldap_config(), 'saved updated LDAP config to YAML';

    # connect w/anonymous bind; should fail
    clear_log();
    $ldap = Socialtext::LDAP->new();
    ok !$ldap, 'anonymous bind fails';
    logged_like 'error', qr/unable to bind/, '... failed to bind';
}

###############################################################################
# Authentication failure.
authentication_failure: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with some data
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added data; people';

    # attempt to authenticate, using wrong password
    clear_log();
    my %opts = (
        user_id     => 'cn=John Doe,dc=example,dc=com',
        password    => 'this-is-the-wrong-password',
    );
    my $authok = Socialtext::LDAP->authenticate(%opts);
    ok !$authok, 'authentication failed';
    logged_like 'info', qr/authentication failed/, '... auth failed';
}

###############################################################################
# Authentication success.
authentication_ok: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with some data
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added data; people';

    # attempt to authenticate, using a known username/password
    my %opts = (
        user_id     => 'cn=John Doe,dc=example,dc=com',
        password    => 'foobar',
    );
    my $authok = Socialtext::LDAP->authenticate(%opts);
    ok $authok, 'authentication ok';
}

###############################################################################
# Search, no results.
search_no_results: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with some data
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added data; people';

    # search should execute ok, but have no results
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'connected to OpenLDAP';

    my $mesg = $ldap->search(
        base    => $openldap->base_dn(),
        filter  => '(cn=This User Does Not Exist)',
        );
    ok !$mesg->code(), 'search executed successfully';
    is $mesg->count(), 0, 'search returned zero results';
}

###############################################################################
# Search, with results.
search_with_results: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with some data
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added data; people';

    # searches should execute ok, and contain correct number of results
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'connected to OpenLDAP';

    my $mesg = $ldap->search(
        base    => $openldap->base_dn(),
        filter  => '(mail=*)',
        );
    ok !$mesg->code(), 'search executed successfully';
    is $mesg->count(), 6, 'search returned three results';

    $mesg = $ldap->search(
        base    => $openldap->base_dn(),
        filter  => '(telephoneNumber=*)',
        );
    ok !$mesg->code(), 'search executed successfully';
    is $mesg->count(), 1, 'search returned one result';
}

###############################################################################
# Search with -NO- global "filter"; should return both "users" and "contacts"
search_without_filter_gets_users_and_contacts: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with some data
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added data; people';
    ok $openldap->add_ldif('t/test-data/ldap/contacts.ldif'), 'added data; contacts';

    # clear any filter in the LDAP config
    $openldap->ldap_config->filter(undef);
    $openldap->add_to_ldap_config();

    # check to make sure that LDAP config has -NO- filter in it
    my $ldap = Socialtext::LDAP->new();
    isa_ok $ldap, 'Socialtext::LDAP::OpenLDAP', 'connected to OpenLDAP';
    ok !$ldap->config->filter(), 'no global "filter" defined in config';

    # unfiltered results should get multiple results
    my $mesg = $ldap->search(
        base    => $openldap->base_dn(),
        filter  => '(cn=John Doe)',
        attrs   => ['objectClass'],
        );
    ok !$mesg->code(), 'search executed successfully';
    is $mesg->count(), 2, 'search returned two results';

    my @entries = $mesg->entries();
    my $inetOrgPerson        = grep { $_->get_value('objectClass') eq 'inetOrgPerson'        } @entries;
    my $organizationalPerson = grep { $_->get_value('objectClass') eq 'organizationalPerson' } @entries;
    ok $inetOrgPerson, 'one result was an inetOrgPerson';
    ok $organizationalPerson, 'one result was an organizationalPerson';
}
