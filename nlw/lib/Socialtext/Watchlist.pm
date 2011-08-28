# @COPYRIGHT@
package Socialtext::Watchlist;

use strict;
use warnings;

our $VERSION = '0.01';

use DBI;
use Socialtext::Schema;
use Class::Field 'field';
use Readonly;
use Socialtext::SQL qw( sql_execute sql_format_timestamptz );
use Socialtext::String;
use Socialtext::MultiCursor;

field 'user_id';
field 'workspace_id';

sub new {
    my $class = shift;
    my %p = @_;

    return bless {
        user_id      => $p{user}->user_id(),
        workspace_id => $p{workspace}->workspace_id(),
    }, $class;
}

sub has_page {
    my ( $self, %p ) = @_;

    my $sth = sql_execute(
        'SELECT user_id FROM "Watchlist" '
            . 'WHERE user_id=? AND workspace_id=? AND page_text_id=?',
        $self->{user_id}, $self->{workspace_id}, $p{page}->id() );

    return scalar @{ $sth->fetchall_arrayref };
}

sub add_page {
    my ( $self, %p ) = @_;

    sql_execute(
        'INSERT INTO "Watchlist" '
        . '(user_id, workspace_id, page_text_id) VALUES (?,?,?)',
        $self->{user_id}, $self->{workspace_id}, $p{page}->id() );
}

sub remove_page {
    my ( $self, %p ) = @_;

    sql_execute(
        'DELETE FROM "Watchlist" '
        . 'WHERE user_id=? AND workspace_id=? AND page_text_id=?',
        $self->{user_id}, $self->{workspace_id}, $p{page}->id() );
}

sub pages {
    my $self = shift;
    my %p    = @_;

    my @args = ($p{limit});

    my $new_as = '';
    if ($p{new_as}) {
        $new_as = 'AND p.last_edit_time >= ?::timestamptz';
        unshift @args, sql_format_timestamptz(
            DateTime->from_epoch(epoch => $p{new_as})
        );
    }

    my $sth = sql_execute( <<EOT,
SELECT page_text_id 
    FROM "Watchlist" w
        LEFT JOIN page p ON (w.workspace_id = p.workspace_id 
                        AND w.page_text_id = p.page_id)
    WHERE w.user_id = ? AND w.workspace_id = ? $new_as
    ORDER BY p.last_edit_time DESC
    LIMIT ?
EOT
        $self->{user_id}, $self->{workspace_id}, @args
    );

    return map { $_->[0] } @{ $sth->fetchall_arrayref };
}

sub Users_watching_page {
    my $class        = shift;
    my $workspace_id = shift;
    my $page_id      = shift;
    my $userids_only = shift;

    my $sth = sql_execute( <<EOT, $workspace_id, $page_id );
SELECT user_id
    FROM "Watchlist"
    WHERE workspace_id = ? AND page_text_id = ?
EOT

    return [ map { $_->[0] } @{ $sth->fetchall_arrayref } ];
}

1;

__END__

=head1 NAME

Socialtext::Watchlist - Represents a watchlist for a user in a given workspace

=head1 SYNOPSIS

    my $watchlist = Socialtext::Watchlist->new(
        user      => $user,
        workspace => $ws,
    );

=head1 DESCRIPTION

The Watchlist is designed to allow users to select which pages in a wiki
they would like to keep track of.

Each watchlist object refers to a single workspace/user combination.

=head1 METHODS

=head2 Socialtext::Watchlist->new( user => $user, workspace => $ws )

Creates an object representing C<$user>'s watchlist in the workspace C<$ws>.

=head2 $watchlist->has_page( $page )

Returns true iff the C<$page> is in C<$watchlist>.

=head2 add_page( $page )

Adds the specified page to the watchlist

=head2 remove_page( $page )

Removes the specified page from the watchlist

=head2 $watchlist->pages()

Returns a list of the C<page_id>s of all pages in the given watchlist.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut
