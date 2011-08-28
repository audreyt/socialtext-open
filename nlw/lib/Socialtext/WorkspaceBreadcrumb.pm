# @COPYRIGHT@
package Socialtext::WorkspaceBreadcrumb;
use strict;
use warnings;

use Class::Field 'field';
use DateTime::Format::Pg;
use Socialtext::MultiCursor;
use Socialtext::Schema;
use Socialtext::SQL qw( sql_execute );
use Socialtext::Workspace;
use Socialtext::SQL qw( sql_execute sql_selectrow );
use Socialtext::Permission qw( ST_EMAIL_IN_PERM ST_READ_PERM );
use Socialtext::UserSet qw/:const/;

field 'workspace_id';
field 'user_id';
field 'timestamp';

sub new {
    my ( $class, %p ) = @_;

    my $new_crumb = bless {
        user_id      => $p{user_id},
        workspace_id => $p{workspace_id},
    },
    $class;

    return $new_crumb->_refresh_from_db ? $new_crumb : undef;
}

sub create {
    my ( $class, %p ) = @_;

    my $sth = sql_execute(
        'INSERT INTO "WorkspaceBreadcrumb" (user_id, workspace_id)'
        . ' VALUES (?,?)', $p{user_id}, $p{workspace_id} );
    return $class->new(%p);
}

sub _refresh_from_db {
    my ($self) = @_;

    my $sth = sql_execute(
        'SELECT timestamp FROM "WorkspaceBreadcrumb"'
        . ' WHERE user_id=? AND workspace_id=?',
        $self->{user_id}, $self->{workspace_id} );

    my @rows = @{ $sth->fetchall_arrayref };
    if (@rows) {
        $self->{timestamp} = $rows[0][0];
        return 1;
    } else {
        return 0;
    }
}

sub update_timestamp {
    # Need to compose the "set" phrase from %p and the "where" phrase from $self
    my ($self, %p) = @_;

    sql_execute(
        'UPDATE "WorkspaceBreadcrumb" SET'
        . ' timestamp=now() WHERE user_id=? AND workspace_id=?',
        $self->{user_id}, $self->{workspace_id} );
    $self->_refresh_from_db;

    return $self;
}

sub List {
    my ( $class, %p ) = @_;
    my $sth = sql_execute( qq{
     SELECT wb.workspace_id FROM "WorkspaceBreadcrumb" wb
        WHERE wb.user_id=?
        AND ( EXISTS (SELECT 1 FROM user_set_path path
                WHERE wb.user_id = path.from_set_id
                  AND wb.workspace_id + } . PG_WKSP_OFFSET . qq{ = into_set_id)
            OR EXISTS (SELECT 1 FROM "WorkspaceRolePermission" wrp
                WHERE wrp.workspace_id = wb.workspace_id
                  AND wrp.role_id=? AND wrp.permission_id=?)
            )
        ORDER BY wb.timestamp DESC LIMIT ?},
        $p{user_id},
        Socialtext::Role->Guest()->role_id,
        ST_READ_PERM->permission_id,
        $p{limit} );
    return
        map { Socialtext::Workspace->new( workspace_id => $_->[0] ) }
        @{ $sth->fetchall_arrayref };
}

sub Save {
    my $class = shift;

    my $crumb = $class->new(@_);
    if ($crumb) {
        $crumb->update_timestamp();
        return $crumb;
    }
    else {
        return $class->create(@_);
    }
}

sub parsed_timestamp {
    my $self = shift;
    return DateTime::Format::Pg->parse_timestamptz( $self->timestamp );
}

1;

__END__

=head1 NAME

Socialtext::WorkspaceBreadcrumb - Workspace Breadcrumbs

=head1 SYNOPSIS


    # Save breadcrumb
    Socialtext::WorkspaceBreadcrumb->Save(
        user_id => 1,
        workspace_id => 1
    );

    # Get breadcrumbs
    my @workspaces
        = Socialtext::WorkspaceBreadcrumb->List( user_id => 1, limit => 5 );

=head1 DESCRIPTION

This class provides methods for dealing with data from the
WorkspaceBreadcrumb table.

=head1 CLASS METHODS

=over 4

=item Socialtext::WorkspaceBreadcrumb->Save(PARAMS)

Saves a breadcrumb to the table, and return a breadcrumb
C<Socialtext::WorkspaceBreadcrumb> object representing that row.

PARAMS I<must> be:

=over 8

=item * user_id => $user_id

=item * workspace_id => $workspace_id

=back

=item Socialtext::WorkspaceBreadcrumb->List(PARAMS)

Retrieves the last N workspaces visited by the given user id.  The list is a
list of C<Socialtext::Workspace> objects.

PARAMS can include:

=over 8

=item * user_id - required

=item * limit - defaults to 10

=back

=back

=head1 INSTANCE METHODS

=over 4

=item parsed_timestamp()

Returns a DateTime object representing for the time the breadcrumb was
created.

=item timestamp()

Returns a raw string representing the time the breadcrumb was created.

=item workspace_id()

Returns a workspace id for the visited workspace this breadcrumb represents.

=item user_id()

Returns a user id for the user who visited some workspace this breadcrumb
represents.

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
