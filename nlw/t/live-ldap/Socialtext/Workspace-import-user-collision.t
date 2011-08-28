#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Temp qw();
use Socialtext::Account;
use Socialtext::LDAP;
use Socialtext::LDAP::Config;
use Socialtext::SQL::Builder qw/:all/;
use Socialtext::User;
use Socialtext::Workspace;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 10;

###############################################################################
# FIXTURE:  db
#
# Need to have the DB available, but don't care what's in it
fixtures( 'db', 'destructive' );

###############################################################################
# LDAP users have multiple possible keys that they can be looked up (email,
# username, dn).  Default users, OTOH, only have one (email) (which is *also*
# their username).
#
# When importing a Workspace back into an LDAP-enabled appliance, we *need* to
# make sure that we're looking up across all of these keys.  Otherwise, we run
# into problems where we didn't find the User in LDAP and then try to recreate
# a new User record for them *BUT* this creates a conflict/collision on
# duplicate e-mail address (thus botching the import).
###############################################################################


###############################################################################
# Create a test/dummy Workspace to work with.
my $ws_name = 'user-collision';
my $ws = Socialtext::Workspace->create(
    name       => $ws_name,
    title      => $ws_name,
    account_id => Socialtext::Account->Default->account_id
);
isa_ok $ws, 'Socialtext::Workspace';

###############################################################################
# Create a test User to work with.  This user *will* exist in LDAP later on;
# he's one of the test Users in `t/test-data/ldap/people.ldif`
my $email   = 'ray.parker@example.com';
my $user = Socialtext::User->create(
    username      => $email,
    email_address => $email
);
isa_ok $user, 'Socialtext::User';

$ws->add_user( user => $user );
ok $ws->has_user( $user );

###############################################################################
# Export the Workspace, then nuke it outright.
my $tmpdir  = File::Temp::tempdir(CLEANUP => 1);
my $tarball = $ws->export_to_tarball(dir => $tmpdir);
ok ( -f $tarball );

$ws->delete;

###############################################################################
# Fire up LDAP, and populate it with some users.
my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
isa_ok $ldap, 'Test::Socialtext::Bootstrap::OpenLDAP';

# ... populate OpenLDAP
ok $ldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
ok $ldap->add_ldif('t/test-data/ldap/people.ldif'), 'added people';

###############################################################################
# MANUALLY migrate the User in the DB, using a process similar to what's done
# in `migrate-to-ldap` right now.
my $user_id = $user->user_id;
my $prototype = Socialtext::User->_first('lookup',
    email_address => $user->email_address);

my $ldap_hash = {
    driver_username => $prototype->{username},
    cached_at       => 'now',
    password        => '*no-password*',
    user_id         => $user_id,
};

sql_update('users', $ldap_hash, 'user_id');

###############################################################################
# Double-check to make sure that if we instantiate the User in LDAP that we
# find him there.
my $ldap_user = Socialtext::User->new( email_address => $email );
ok $ldap_user, 'Socialtext::User';
ok $ldap_user->homunculus, 'Socialtext::User::LDAP';

###############################################################################
# Re-import our Workspace.
#
# If we're doing this correctly, we match up the User against the one from
# LDAP and things are good.  If we're *not* then we try to create a new User
# in the DB and explode/die on email conflict/collision.
my $imported_workspace
    = Socialtext::Workspace->ImportFromTarball(tarball => $tarball);

ok $imported_workspace, 'Socialtext::Workspace';
