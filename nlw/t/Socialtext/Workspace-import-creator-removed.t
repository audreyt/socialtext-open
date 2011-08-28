#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences;
use Socialtext::Role;
use Socialtext::Workspace;

fixtures('db');

my ($ws_name, $expected, $tarball);

setup: {
    my $creator = create_test_user();
    my $admin = create_test_user();
    my $member = create_test_user();
    my $ws = create_test_workspace(user=>$creator);

    $ws_name = $ws->name;
    $expected = {
        $admin->username => 'admin',
        $member->username => 'member',
    };

    $ws->add_user(actor=>$creator, user=>$admin, role=>Socialtext::Role->Admin);
    $ws->add_user(actor=>$creator, user=>$member);
    $ws->remove_user(actor=>$creator, user=>$creator);

    eq_or_diff roles_for_workspace($ws), $expected,
        'proper roles before export/import';

    $tarball = export_and_remove($ws);
}

import_and_test: {
    Socialtext::Workspace->ImportFromTarball( tarball => $tarball );

    my $ws = Socialtext::Workspace->new(name => $ws_name);
    eq_or_diff roles_for_workspace($ws), $expected,
        'proper roles after export/import';
}

done_testing;
exit;
################################################################################

sub export_and_remove {
    my $ws = shift;
    my $test_dir = Socialtext::AppConfig->test_dir();

    my $tarball = $ws->export_to_tarball(dir => $test_dir);

    Test::Socialtext::User->delete_recklessly($_) for $ws->users->all;
    $ws->delete();

    return $tarball;
}

sub roles_for_workspace {
    my $ws = shift;
    
    return +{ map { $_->[0]->username => $_->[1]->name }
        $ws->user_roles->all };
}
