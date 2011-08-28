#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::LDAP;
use Socialtext::Workspace;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 20;

###############################################################################
# FIXTURE: db
###############################################################################
fixtures(qw( db ));

###############################################################################
# What happens if we have a user in an LDAP store and then take away that data
# store entirely?
#
# This is somewhat of a lengthy test; we've got a lot of setup to do to get
# the user store, workspace, and user stuff all created, long before we even
# try removing the store and seeing what happens.
disappearing_ldap_user_store: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), '... added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), '... added data: people';

    # instantiate the user, and add them to a test workspace.
    my $ws   = create_test_workspace();
    my $user = Socialtext::User->new( username => 'John Doe' );
    isa_ok $user, 'Socialtext::User', 'found user to test with';
    isa_ok $user->homunculus(), 'Socialtext::User::LDAP', '... which came from the LDAP store';
    my $dn = $user->homunculus->driver_unique_id;

    $ws->add_user( user => $user );
    pass 'added the user to the workspace';

    # enumerate the users in the test workspace; one of them should be an
    # "LDAP" user.
    my $cursor  = $ws->user_roles();
    my @entries = map { $_->[0] } $cursor->all();
    ok @entries, 'got list of users in the workspace';

    my @ldap_users = grep { ref($_->homunculus) eq 'Socialtext::User::LDAP' } @entries;
    is scalar @ldap_users, 1, '... one of which is an LDAP user';
    is $ldap_users[0]->user_id, $user->user_id, '... ... our test user';

    my @deleted_users = grep { $_->is_deleted } @entries;
    ok !@deleted_users, '... none of which are Deleted users';

    # shut down OpenLDAP, which automatically removes *ALL* of the config that
    # pointed towards its existence.
    undef $openldap;

    # enumerate the users in the test workspace again; we should still be able
    # to do so, but now the user from the LDAP store is a "Deleted" user.
    $cursor  = $ws->user_roles();
    @entries = map { $_->[0] } $cursor->all();
    ok @entries, 'got list of users in the workspace';

    @ldap_users = grep { ref($_->homunculus) eq 'Socialtext::User::LDAP' } @entries;
    ok !@ldap_users, '... none of which are LDAP users';

    @deleted_users = grep { $_->is_deleted() } @entries;
    is scalar @deleted_users, 1, '... one of which is a Deleted user';
    is $deleted_users[0]->user_id, $user->user_id, '... ... our test user';

    # lookup the user by other means
    my $maybe_deleted = Socialtext::User->new(username => $user->username);
    ok $maybe_deleted, "got the user by username";
    ok $maybe_deleted->is_deleted, "... and it's deleted";

    $maybe_deleted = Socialtext::User->new(email_address => $user->email_address);
    ok $maybe_deleted, "got the user by email_address";
    ok $maybe_deleted->is_deleted, "... and it's deleted";

    $maybe_deleted = Socialtext::User->new(driver_unique_id => $dn);
    ok $maybe_deleted, "got the user by driver_unique_id";
    ok $maybe_deleted->is_deleted, "... and it's deleted";
}
