#!perl
# @COPYRIGHT@

use strict;
use warnings;
use DateTime::Format::Pg;
use Socialtext::Workspace;
use Test::Socialtext tests => 28;

###############################################################################
# Fixtures: clean populated_rdbms
# - this test expects a known fresh/clean state to start with
fixtures(qw( clean populated_rdbms destructive ));

sub workspace_names {
    my $workspaces = shift;
    return [map { $_->name } $workspaces->all()];
}
        
{
    my $workspaces;
    $workspaces = Socialtext::Workspace->All();
    # This is to remove the "central" AUWs
    for my $ws ($workspaces->all) {
        $ws->delete if $ws->name =~ /_central$/;
    }


    $workspaces = Socialtext::Workspace->All();
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 0..9 ],
        'All() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->All( limit => 2 );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace0 workspace1 ) ],
        'All() limit of 2',
    );

    $workspaces = Socialtext::Workspace->All( limit => 2, offset => 2 );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace2 workspace3 ) ],
        'All() limit of 2, offset of 2',
    );

    $workspaces = Socialtext::Workspace->All( sort_order => 'DESC' );
    is_deeply(
        workspace_names($workspaces),
        [ reverse map { ("workspace$_") } 0..9 ],
        'All() in DESC order',
    );

    # Since ws 7-10 have the same number of users each, they come out
    # first, but sorted by name in ascending order.
    $workspaces = Socialtext::Workspace->All( order_by => 'user_count', sort_order => 'DESC' );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 6, 7, 8, 9, 5, 4, 2, 3, 1, 0 ],
        'All() sorted by DESC user_count',
    );

    $workspaces = Socialtext::Workspace->All( order_by => 'account_name' );
    is join(',', @{workspace_names($workspaces)} ),
       join(',', map { "workspace$_" } qw/0 2 4 6 8 1 3 5 7 9/),
       'All() sorted by account_name';

    $workspaces = Socialtext::Workspace->All( order_by => 'creation_datetime' );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 0..9 ],
        'All() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->All( order_by => 'creator' );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 6, 5, 4, 3, 2, 9, 1, 8, 0, 7  ],
        'All() sorted by creator',
    );
}

{
    my $account_id = Socialtext::Account->new(name => 'Other 1')->account_id;
    my $workspaces = Socialtext::Workspace->ByAccountId( account_id => $account_id );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 0, 2, 4, 6, 8 ],
        'ByAccountId() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        limit      => 2,
    );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace0 workspace2 ) ],
        'ByAccountId() limit of 2',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        limit      => 2,
        offset     => 2,
    );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace4 workspace6 ) ],
        'ByAccountId() limit of 2, offset of 2',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        sort_order => 'DESC',
    );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 8, 6, 4, 2, 0 ],
        'ByAccountId() in DESC order',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'user_count',
    );
    is_deeply(
        [ map { [$_->name, $_->user_count] } $workspaces->all() ],
        [ map { ["workspace$_->[0]", $_->[1]] } 
            [0, 2], [2, 4], [4, 5], [6, 7], [8, 7] ],
        'ByAccountId() sorted by user_count',
    );

    # Since ws 7-10 have the same number of users each, they come out
    # first, but sorted by name in ascending order.
    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'user_count',
        sort_order => 'DESC',
    );
    is_deeply(
        [ map { [$_->name, $_->user_count] } $workspaces->all() ],
        [ map { ["workspace$_->[0]", $_->[1]] } 
            [6, 7], [8, 7], [4, 5], [2, 4], [0, 2] ],
        'ByAccountId() sorted by DESC user_count',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'creation_datetime',
    );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 0, 2, 4, 6, 8 ],
        'ByAccountId() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->ByAccountId(
        account_id => $account_id,
        order_by   => 'creator',
    );
    is_deeply(
        workspace_names($workspaces),
        [ map { ("workspace$_") } 6, 4, 2, 8, 0 ],
        'ByAccountId() sorted by creator',
    );
}

{
    # We want to make sure that these workspaces have a known
    # creation_datetime, just for simplicity when testing ordering by
    # creation_datetime.
    my $now = DateTime->now();
    Socialtext::Workspace->create(
        name              => 'workspace10',
        title             => 'Workspace 10',
        account_id        =>
            Socialtext::Account->new( name => 'Other 1')->account_id,
        creation_datetime =>
            DateTime::Format::Pg->format_timestamptz($now),
    );

    my $ws = Socialtext::Workspace->create(
        name       => 'number-111',
        title      => 'Number 111',
        account_id =>
            Socialtext::Account->new( name => 'Other 2')->account_id,
        creation_datetime =>
            DateTime::Format::Pg->format_timestamptz($now),
    );

    for my $username ( qw( devnull6@socialtext.com devnull7@socialtext.com ) ) {
        my $user = Socialtext::User->new( username => $username );
        $ws->add_user( user => $user );
    }

    is( Socialtext::Workspace->CountByName( name => '1' ), 3,
        'Three workspaces match "%1%"' );

    Case_insensitivity: {
        is( Socialtext::Workspace->CountByName( name => 'nUmBeR' ), 0,
            'Zero workspaces match "%nUmBeR%" case-sensitive' );

        is( Socialtext::Workspace->CountByName( name => 'nUmBeR', case_insensitive => 1 ), 1,
            'One workspaces match "%nUmBeR%" case-insensitive' );
    }

    my $workspaces = Socialtext::Workspace->ByName( name => '1' );
    is_deeply(
        workspace_names($workspaces),
        [ qw( number-111 workspace1 workspace10 ) ],
        'ByName() returns workspaces sorted by name by default',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', limit => 2  );
    is_deeply(
        workspace_names($workspaces),
        [ qw( number-111 workspace1 ) ],
        'ByName() limit of 2',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', limit => 2, offset => 1 );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace1 workspace10 ) ],
        'ByName() limit of 2, offset of 1',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', sort_order => 'DESC' );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace10 workspace1 number-111 ) ],
        'ByName() in DESC order',
    );

    Sorting_by_user_count: {
        # XXX This sort order isn't correct, as workspaces with no
        # users come last (b/c SQL returns a null, not a 0).  We're
        # going to live with this for now, as workspaces with 0 users
        # are very uncommon.
        $workspaces = Socialtext::Workspace->ByName(
            name     => '1',
            order_by => 'user_count',
        );
        is_deeply(
            [ map { [$_->name, $_->user_count] } $workspaces->all ],
            [ 
              ['number-111' => 2], 
              ['workspace1' => 3], 
              ['workspace10' => 0],
            ],
            'ByName() sorted by user_count',
        );

        # XXX This sort order isn't correct b/c of workspaces with no users.
        # See above comment.
        $workspaces = Socialtext::Workspace->ByName(
            name     => '1',
            order_by => 'user_count',
            sort_order => 'DESC',
        );
        is_deeply(
            [ map { [$_->name, $_->user_count] } $workspaces->all() ],
            [ 
              ['workspace10' => 0],
              ['workspace1' => 3], 
              ['number-111' => 2], 
            ],
            'ByName() sorted by user_count DESC',
        );
    }

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'account_name' );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace10 number-111 workspace1 ) ],
        'ByName() sorted by account_name',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'creation_datetime' );
    is_deeply(
        workspace_names($workspaces),
        [ qw( number-111  workspace10 workspace1 ) ],
        'ByName() sorted by creation_datetime',
    );

    $workspaces = Socialtext::Workspace->ByName( name => '1', order_by => 'creator' );
    is_deeply(
        workspace_names($workspaces),
        [ qw( workspace1 number-111 workspace10 ) ],
        'ByName() sorted by creator',
    );
}

