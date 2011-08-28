#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
use Socialtext::Role;
use Socialtext::Permission qw/ST_LOCK_PERM/;
fixtures( 'db', 'destructive' );

version_0: {
    my $ws_name = 'version-zero';
    my $tarball = 't/test-data/export-tarballs/admin.tar.gz';
    Socialtext::Workspace->ImportFromTarball( 
        tarball => $tarball,
        overwrite => 1,
        name => $ws_name,
    );

    my $hub = new_hub($ws_name);
    my $ws = $hub->current_workspace;

    ok ($ws->permissions->role_can(
        role => Socialtext::Role->Admin(),
        permission => ST_LOCK_PERM ), 
    'admin has the lock permission on v0 import.');
}

version1: {
    my $tarball = 't/test-data/export-tarballs/admin.1.tar.gz';
    Socialtext::Workspace->ImportFromTarball( 
        tarball => $tarball,
        overwrite => 1
    );

    my $hub = new_hub('admin');
    my $ws = $hub->current_workspace;

    ok ($ws->permissions->role_can(
        role => Socialtext::Role->Admin(),
        permission => ST_LOCK_PERM ), 
    'admin has the lock permission on v1 import.');
}
