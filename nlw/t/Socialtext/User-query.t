#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::User;
use Test::Socialtext tests => 32;
use Test::Differences;

###############################################################################
# Fixtures: clean populated_rdbms
# - this test expects a known fresh/clean state to start with
fixtures(qw( clean populated_rdbms ));

{
    my $users = Socialtext::User->All();
    is_deeply(
        [ map { $_->username } $users->all() ],
        [
            ( map { ("devnull$_\@socialtext.com") } 1 .. 7 ),
             'guest', 'system-user'
        ],
        'All() returns users sorted by name by default',
    );
    is( join(',', map { $_->primary_account->name } $users->all()),
        'Other 1,Other 2,Other 1,Other 2,Other 1,Other 2,Other 1,'
        . 'Socialtext,Socialtext',
        'Primary accounts are set as expected',
    );

    $users = Socialtext::User->All( limit => 2 );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 1 .. 2 ],
        'All() limit of 2',
    );

    $users = Socialtext::User->All( limit => 2, offset => 2 );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 3 .. 4 ],
        'All() limit of 2',
    );

    $users = Socialtext::User->All( sort_order => 'DESC' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [
            'system-user', 'guest',
            reverse map { ("devnull$_\@socialtext.com") } 1 .. 7
        ],
        'All() in DESC order',
    );

    $users = Socialtext::User->All( order_by => 'workspace_count' );
    eq_or_diff(
        [ map { $_->username } $users->all() ],
        [
            'guest', 'system-user',
            map { ("devnull$_\@socialtext.com") } 7, 6, 4, 5, 3, 2, 1
        ],
        'All() sorted by workspace_count',
    );

    $users = Socialtext::User->All( order_by => 'creation_datetime' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [
            'guest', 'system-user',
            ( map { ("devnull$_\@socialtext.com") } (1..7) ),
        ],
        'All() sorted by creation_datetime',
    );

    $users = Socialtext::User->All( order_by => 'creator' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [
            ( map { ("devnull$_\@socialtext.com") } 3, 4, 5, 6, 7, 1, 2 ),
            'guest', 'system-user'
        ],
        'All() sorted by creator',
    );

    my $user = Socialtext::User->Resolve( 'devnull1@socialtext.com' );
    my $account = Socialtext::Account->new(name => 'Other 1');
    $user->primary_account( $account );
    $users = Socialtext::User->All( 
        order_by   => 'primary_account',
        sort_order => 'desc'
    );
    # Check the t/Fixtures/populated_rdbms/generate script for up-to-date
    # info, but users are added to either the Other 1 or Other 2 accounts.
    is( join(',', map { $_->username } $users->all() ),
        'system-user,guest,devnull2@socialtext.com,devnull4@socialtext.com,'
        . 'devnull6@socialtext.com,devnull1@socialtext.com,devnull3@socialtext.com,'
        . 'devnull5@socialtext.com,devnull7@socialtext.com',
        'All() sorted by primary account name',
    );
}
{
    my $ids = [ 1, 2, 3 ];
    my $users = Socialtext::User->ByUserIds( $ids );

    is( join(',', map { $_->username } $users->all() ),
        'system-user,guest,devnull1@socialtext.com',
        'ByUserIds() returns users in the order that IDs are passed.'
    );
}

{
    my $ws = Socialtext::Workspace->new( name => 'workspace6' );
    my $users = $ws->users();

    my %roles;
    while ( my $user = $users->next() ) {
        $roles{ $user->username }
            = $ws->role_for_user($user)->name();
    }

    my $ws_id = $ws->workspace_id;

    my $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [ map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } 1 .. 7 ],
        'ByWorkspaceIdWithRoles() returns users sorted by name by default',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        limit        => 2,
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [ map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } 1 .. 2 ],
        'ByWorkspaceIdWithRoles() limit of 2',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        limit        => 2,
        offset       => 2,
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [ map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } 3 .. 4 ],
        'ByWorkspaceIdWithRoles() limit of 2',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        sort_order   => 'DESC',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            reverse map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] }
                1 .. 7
        ],
        'ByWorkspaceIdWithRoles() in DESC order',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by     => 'creation_datetime',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [ map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } (1..7) ],
        'ByWorkspaceIdWithRoles() sorted by creation_datetime',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by     => 'creator',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } 3, 4, 5,
            6, 7, 1, 2
        ],
        'ByWorkspaceIdWithRoles() sorted by creator',
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by     => 'role_name',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [ map { my $u = "devnull$_\@socialtext.com"; [ $u, $roles{$u} ] } 1 .. 7 ],
        'ByWorkspaceIdWithRoles() sorted by role_name',
    );
}

{
    ### These tests verify that we're getting the Groups users out correctly.
    ### Other tests for "are things sorting correctly by 'foo'" are done
    ### above; we're just concerned here that we got the Groups users.
    my $ws    = create_test_workspace();
    my $ws_id = $ws->workspace_id();

    # create some Groups and use those to help define membership for the WS
    my $group_one = create_test_group(account => $ws->account);
    $ws->add_group(
        group => $group_one,
        role  => Socialtext::Role->Impersonator,
    );

    my $group_two = create_test_group(account => $ws->account);
    $ws->add_group(
        group => $group_two,
        role  => Socialtext::Role->Admin,
    );

    # create some other Users and give them access to the WS
    my $user_uwr = create_test_user(account => $ws->account);
    $ws->add_user(user => $user_uwr);

    my $user_uwr_gwr = create_test_user(account => $ws->account);
    $ws->add_user(user => $user_uwr_gwr);
    $group_one->add_user(user => $user_uwr_gwr);

    my $user_gwr_gwr = create_test_user(account => $ws->account);
    $group_one->add_user(user => $user_gwr_gwr);
    $group_two->add_user(user => $user_gwr_gwr);

    # TEST: default sort order
    my $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            [ $user_uwr->username,     'member' ],
            [ $user_uwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'member' ],
            [ $user_gwr_gwr->username, 'admin' ],
            [ $user_gwr_gwr->username, 'impersonator' ],
        ],
        'ByWorkspaceIdWithRoles() with Groups, default ordering'
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by => 'username',
        sort_order => 'DESC',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            [ $user_gwr_gwr->username, 'admin' ],
            [ $user_gwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'member' ],
            [ $user_uwr->username,     'member' ],
        ],
        'ByWorkspaceIdWithRoles() with Groups, reverse username ordering'
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by => 'creation_datetime',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            [ $user_gwr_gwr->username, 'admin' ],
            [ $user_gwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'member' ],
            [ $user_uwr->username,     'member' ],
        ],
        'ByWorkspaceIdWithRoles() with Groups, creation ordering'
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by => 'creator',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            [ $user_uwr->username,     'member' ],
            [ $user_uwr_gwr->username, 'impersonator' ],
            [ $user_uwr_gwr->username, 'member' ],
            [ $user_gwr_gwr->username, 'admin' ],
            [ $user_gwr_gwr->username, 'impersonator' ],
        ],
        'ByWorkspaceIdWithRoles() with Groups, creator ordering'
    );

    $users_with_roles = Socialtext::User->ByWorkspaceIdWithRoles(
        workspace_id => $ws_id,
        order_by => 'role_name',
    );
    is_deeply(
        [
            map { [ $_->[0]->username, $_->[1]->name ] }
                $users_with_roles->all()
        ],
        [
            [ $user_gwr_gwr->username, 'admin' ],
            [ $user_uwr_gwr->username, 'impersonator' ],
            [ $user_gwr_gwr->username, 'impersonator' ],
            [ $user_uwr->username,     'member' ],
            [ $user_uwr_gwr->username, 'member' ],
        ],
        'ByWorkspaceIdWithRoles() with Groups, role_name ordering'
    );
}

{
    is(
        Socialtext::User->CountByUsername( username => '@socialtext' ), 7,
        'seven users have usernames matching "%@socialtext%"'
    );

    my $users = Socialtext::User->ByUsername( username => '@socialtext' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 1 .. 7 ],
        'ByUsername() returns users sorted by name by default',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        limit => 2 );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 1 .. 2 ],
        'ByUsername() limit of 2',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        limit => 2, offset => 2 );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 3 .. 4 ],
        'ByUsername() limit of 2',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        sort_order => 'DESC' );
    is_deeply(
        [ map         { $_->username } $users->all() ],
        [ reverse map { ("devnull$_\@socialtext.com") } 1 .. 7 ],
        'ByUsername() in DESC order',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        order_by => 'workspace_count' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 7, 6, 4, 5, 3, 2, 1 ],
        'ByUsername() sorted by workspace_count',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        order_by => 'creation_datetime' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } (1..7) ],
        'ByUsername() sorted by creation_datetime',
    );

    $users = Socialtext::User->ByUsername( username => '@socialtext',
        order_by => 'creator' );
    is_deeply(
        [ map { $_->username } $users->all() ],
        [ map { ("devnull$_\@socialtext.com") } 3, 4, 5, 6, 7, 1, 2 ],
        'ByUsername() sorted by creator',
    );
}

{
    my $user = create_test_user();
    my $cursor;

    $cursor = Socialtext::User->Query( {
        driver_username => $user->username,
    } );
    is $cursor->count, 1, 'Query() matched User';

    $cursor = Socialtext::User->Query( {
        driver_username => $user->username,
        last_name       => 'blah blah blah blah',
    } );
    is $cursor->count, 0, 'Query() did not match bad user';
}
