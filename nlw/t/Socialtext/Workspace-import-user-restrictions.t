#!/usr/bin/env perl

use strict;
use warnings;
use Test::Socialtext tests => 8;
use Test::Socialtext::User;
use File::Temp qw(tempdir);

fixtures(qw( db ));

###############################################################################
# TEST: User Restrictions survive Workspace export/import
import_user_restrictions: {
    my $user = create_test_user();
    my $ws   = create_test_workspace();
    $ws->add_user(user => $user);
    ok $ws->has_user($user), 'Have workspace, with User as a member';

    $user->add_restriction('email_confirmation');
    $user->add_restriction('password_change');
    my @restrictions = map { $_->to_hash } $user->restrictions->all;
    ok @restrictions, '... User is restricted';

    # Export the WS
    my $username    = $user->username;
    my $ws_name     = $ws->name;
    my $export_base = tempdir(CLEANUP => 1);
    my $tarball     = $ws->export_to_tarball(dir => $export_base);
    ok -e $tarball, '... Workspace has been exported';

    # FLUSH the User + WS out of the system
    $ws->delete();
    Test::Socialtext::User->delete_recklessly($user);

    $ws = Socialtext::Workspace->new(name => $ws_name);
    ok !$ws, '... flushed Workspace';

    $user = Socialtext::User->new(username => $username);
    ok !$user, '... flushed User';

    # Import the WS
    $ws = Socialtext::Workspace->ImportFromTarball(
        tarball   => $tarball,
        overwrite => 1,
    );
    ok $ws, '... Workspace imported';

    # VERIFY: User imported *AND* has his old restrictions
    $user = Socialtext::User->new(username => $username);
    ok $user, '... User imported';

    my @imported = map { $_->to_hash } $user->restrictions->all;
    is_deeply \@imported, \@restrictions, '... ... restrictions imported';
}
