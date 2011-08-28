#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 6;
fixtures(qw( clean db ));

use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::Role;

# Before DB version 97, the 'admin' role was called 'workspace_admin'. We need
# to check that we are compatible with the old 'workspace_admin' role on
# import. The 'still-has-workspace-admin.1.tar.gz' tarball has one
# workspace_admin in it, so we'll import that.

my $ws_name = 'still-called-workspace-admin';
my $admin   = 'b@still-called-workspace-admin.com';
my $member  = 'c@still-called-workspace-admin.com';
my $tarball = "t/test-data/export-tarballs/$ws_name.1.tar.gz";

Socialtext::Workspace->ImportFromTarball( tarball => $tarball );

# Make sure the workspace was imported with the correct permissions
my $ws = Socialtext::Workspace->new( name => $ws_name );
ok $ws, "$ws_name workspace was imported";
is $ws->permissions->current_set_name, 'member-only',
    'workspace permissions were correctly imported';

# This user was a 'member' and should be imported as such
member_user: {
    my $user = Socialtext::User->new( username => $member );

    ok $user, "$member user was imported";
    ok $ws->user_has_role( user => $user, role => Socialtext::Role->Member()),
        "$member is a member, as expected";
}

# This user was a 'workspace_admin', should be imported as 'admin'
admin_user: {
    my $user = Socialtext::User->new( username => $admin );

    ok $user, "$admin user was imported";
    ok $ws->user_has_role(user => $user, role => Socialtext::Role->Admin()),
        "$admin is an admin, as expected";
}
