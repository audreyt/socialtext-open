#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::WorkspaceInvitation;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 12;

fixtures(qw( empty ));

###############################################################################
# We're *testing*, so don't send out any real e-mail messages.
$Socialtext::EmailSender::Base::SendClass = 'Test';

###############################################################################
# TEST: make sure that inviting a new LDAP User to a Workspace auto-vivifies
# an LDAP User record (instead of creating a new Default User record).
inviting_ldap_user_vivifies_ldap_user_record: {
    my $workspace     = Socialtext::Workspace->new(name => 'empty');
    my $system_user   = Socialtext::User->SystemUser();
    my $email_address = 'john.doe@example.com';

    # bootstrap OpenLDAP
    my $guard    = Test::Socialtext::User->snapshot();
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # populate OpenLDAP
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), '... added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), '... added data: people';

    # invite an LDAP User in to a Workspace.
    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace   => $workspace,
        from_user   => $system_user,
        invitee     => $email_address,
    );
    isa_ok $invitation, 'Socialtext::WorkspaceInvitation';
    $invitation->send();

    # see if we can resolve the Id for the User that should have just been
    # created.  Have to do it this way so we don't auto-vivify the User while
    # checking for their existence.
    my $factory = Socialtext::User::LDAP::Factory->new();
    my $user_id = Socialtext::User::LDAP::Factory->ResolveId( {
        driver_key    => $factory->driver_key,
        email_address => $email_address,
    } );
    ok $user_id, 'found user_id for invited User';

    my $invited_user = Socialtext::User->new(user_id => $user_id);
    isa_ok $invited_user, 'Socialtext::User', '... and found User object';
    is $invited_user->homunculus->driver_name, 'LDAP', '... and its an LDAP User';

    # CLEANUP: to not pollute other tests
    Email::Send::Test->clear;
}

###############################################################################
# TODO: make sure that inviting an LDAP User by *e-mail alias* auto-vivifies
# an LDAP User record (instead of creating a new Default User record).
inviting_ldap_user_by_email_alias_vivifies_ldap_user_record: {
    my $workspace     = Socialtext::Workspace->new(name => 'empty');
    my $system_user   = Socialtext::User->SystemUser();
    my $email_address = 'john.doe@example.com';
    my $aliased_email = 'jdoe@example.com';

    # bootstrap OpenLDAP
    my $guard    = Test::Socialtext::User->snapshot();
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # populate OpenLDAP
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), '... added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), '... added data: people';

    # invite an LDAP User in to a Workspace.
    my $invitation = Socialtext::WorkspaceInvitation->new(
        workspace   => $workspace,
        from_user   => $system_user,
        invitee     => $aliased_email,
    );
    isa_ok $invitation, 'Socialtext::WorkspaceInvitation';
    $invitation->send();

    # see if we can resolve the Id for the User that should have just been
    # created.  Have to do it this way so we don't auto-vivify the User while
    # checking for their existence.
    my $factory = Socialtext::User::LDAP::Factory->new();
    my $user_id = Socialtext::User::LDAP::Factory->ResolveId( {
        driver_key    => $factory->driver_key,
        email_address => $email_address,
    } );

    TODO: {
        local $TODO = 'no support for e-mail aliases yet';
        ok $user_id, 'found user_id for invited User';

#        my $invited_user = Socialtext::User->new(user_id => $user_id);
#        isa_ok $invited_user, 'Socialtext::User', '... and found User object';
#        is $invited_user->homunculus->driver_name, 'LDAP', '... and its an LDAP User';
    }
    Email::Send::Test->clear;
}
