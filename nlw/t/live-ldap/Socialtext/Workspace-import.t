#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Archive::Tar;
use File::Temp qw();
use Socialtext::LDAP;
use Socialtext::Workspace;
use Socialtext::Workspace;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 26;
use Test::Socialtext::User;
use Test::Socialtext::Fatal;

###############################################################################
# FIXTURE: foobar
#
# Need to have _some_ workspace available with pages in it that we can export.
###############################################################################
fixtures( 'foobar', 'destructive' );

###############################################################################
# Bug #761; Deleted LDAP user prevents workspace import
#
# Having deleted users at the point of export should not prevent the workspace
# from being able to import again.
#
# Scenario:
#   Customer has LDAP user factories, the "fit hits the shan" and they need to
#   migrate to a new appliance.  The old appliance has *no* connectivity to the
#   LDAP server when the workspaces are exported (so all the users get exported
#   as *deleted users*).
#
#   When workspaces are imported on the new appliance, these deleted users
#   shouldn't prevent the import.  Ideally, the users should be matched up
#   properly against the LDAP user factories on the new appliance, but even if
#   that fails we shouldn't fail catastrophically.
#
# NOTE: as of Aug 12 2009, "Deleted User" objects _no longer_ over-ride the
#       first/last/email attributes.  Thus, deleted Users should get exported
#       using the "last cached data" we had for the LDAP User.
deleted_ldap_user_shouldnt_prevent_workspace_import: {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # populate OpenLDAP
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), '... added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), '... added data: people';

    # instantiate a user and add him to the "foobar" workspace
    my $ws = Socialtext::Workspace->new( name => 'foobar' );
    isa_ok $ws, 'Socialtext::Workspace', 'found "foobar" workspace';

    my $user = Socialtext::User->new( username => 'John Doe' );
    isa_ok $user, 'Socialtext::User', 'found user to test with';
    isa_ok $user->homunculus(), 'Socialtext::User::LDAP',
        '... which came from the LDAP store';

    $ws->add_user(user => $user);
    ok $ws->has_user($user), 'user added to test workspace';

    ###########################################################################
    # simulate loss of connectivity to the LDAP directory
    $openldap = undef;

    # Due to long-term LDAP user caching, we still return the record when we
    # can't connect to the LDAP server (even if it's expired).
    # Make the user look like he came from another factory, which should
    # trigger the old "Deleted" behaviour.
    use Socialtext::SQL qw(sql_execute);
    sql_execute(q{
         UPDATE users 
         SET driver_key = 'Fubar',
             cached_at = '-infinity'
         WHERE user_id = ?
        }, 
        $user->user_id
    );
    my $deleted = Socialtext::User->new( username => 'John Doe' );
    isa_ok $deleted, 'Socialtext::User', 'found user to test with';
    ok $deleted->is_deleted(), '... which now appears as deleted';

    ###########################################################################
    # export/delete the workspace+user, and verify that the LDAP user was
    # exported as a "Deleted User".
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);

    my $tarball = $ws->export_to_tarball(dir => $tmpdir);
    ok -e $tarball, 'workspace exported to tarball';

    $ws->delete();
    Test::Socialtext::User->delete_recklessly($user);
    $ws = undef;

    my $archive = Archive::Tar->new($tarball, 1);
    isa_ok $archive, 'Archive::Tar', 'exported workspace tarball';
    ok $archive->contains_file('foobar-users.yaml'), '... containing user list';

    my $user_yaml = $archive->get_content('foobar-users.yaml');
    my $users = YAML::Load($user_yaml);
    ok defined $users, '... which could be parsed as valid YAML';

    my ($john_doe) = grep { $_->{email_address} eq 'john.doe@example.com' }
        @{$users};
    ok defined $john_doe, '... ... and which contained our test user';

    ###########################################################################
    # re-rig LDAP, just like if we'd been moved to a new appliance

    # bootstrap an entirely new OpenLDAP instance
    $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

    # populate OpenLDAP
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), '... added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), '... added data: people';

    ###########################################################################
    # Import the workspace

    # shouldn't fail catastrophically
    ok !exception { Socialtext::Workspace->ImportFromTarball(tarball=>$tarball) }, 'workspace imported without error';
    $ws = Socialtext::Workspace->new( name => 'foobar' );
    isa_ok $ws, 'Socialtext::Workspace';

    # user should exist in the new workspace, coming from the new LDAP store
    my $imported_user = Socialtext::User->new( username => 'John Doe' );
    isa_ok $imported_user, 'Socialtext::User', 'test user was imported';
    isa_ok $imported_user->homunculus(), 'Socialtext::User::LDAP', '... and found in LDAP store';
    is $imported_user->homunculus->driver_id(), $openldap->ldap_config->id(), '... ... from our *new* LDAP store';
    ok $ws->has_user($imported_user), '... and is a member of our test workspace';

    # user data should match that of the original user
    is $imported_user->first_name(), $user->first_name(), '... has correct first name';
    is $imported_user->last_name(), $user->last_name(), '... has correct last name';
    is $imported_user->email_address(), $user->email_address(), '... has correct e-mail address';

    ###########################################################################
    # unlink the tarball now that we're done with it.
    unlink $tarball;
}
