#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 4;
use Test::Output qw/stderr_like/;
use Socialtext::Workspace;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::Cache;
use File::Temp qw(tempdir);
fixtures('db');

my $user = create_test_user();
my $username = $user->username;
my $ws = create_test_workspace(user => $user);
my $ws_name = $ws->name;

sql_execute(q{UPDATE "UserMetadata" SET is_system_created = true WHERE user_id = ?}, $user->user_id);

Socialtext::Cache->clear();
$user = Socialtext::User->new(username => $username);
ok $user->is_system_created;

system_user_import: {
    my $export_base = tempdir(CLEANUP => 1);
    my $tarball = $ws->export_to_tarball(dir => $export_base);

    # reckless delete will leave the ws dir hanging around, so clean it up
    # first:
    $ws->delete();
    Test::Socialtext::User->delete_recklessly($user);

    stderr_like {
        Socialtext::Workspace->ImportFromTarball( 
            tarball => $tarball,
            overwrite => 1
        );
    } qr/\Q$username\E was system created. Importing as regular user./;

    $ws = Socialtext::Workspace->new(name => $ws_name);
    $user = Socialtext::User->new(username => $username);
    is $ws->role_for_user($user, direct => 1)->name, 'admin';
    ok !$user->is_system_created;
}
