# @COPYRIGHT@
package Socialtext::Workspace::Permissions;
use strict;
use warnings;
use Readonly;
use List::Util qw(first);
use Socialtext::Cache;
use Socialtext::SQL qw(get_dbh sql_execute :txn);
use Socialtext::Validate qw(
    validate validate_pos SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE
    HANDLE_TYPE URI_TYPE USER_TYPE ROLE_TYPE PERMISSION_TYPE FILE_TYPE
    DIR_TYPE UNDEF_TYPE
);
use Socialtext::Permission qw( ST_EMAIL_IN_PERM ST_READ_PERM ST_EDIT_CONTROLS_PERM );
use Socialtext::l10n qw(loc system_locale __);
use Socialtext::Exceptions qw( rethrow_exception );
use Socialtext::Role;
use Socialtext::Timer qw/time_scope/;

our %AllowableRoles = map { $_ => 1 }
    qw/guest authenticated_user account_user   affiliate member admin impersonator/;

our %PermissionSets = (
  'public' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw( read edit             comment        email_in                                )],
    authenticated_user => [qw( read edit             comment        email_in                                )],
    guest              => [qw( read edit             comment                                                )],
  },
  'member-only' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw(                                      email_in                                )],
    authenticated_user => [qw(                                      email_in                                )],
    guest              => [                                                                                  ],
  },
  'authenticated-user-only' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw( read edit attachments comment delete email_in email_out                      )],
    authenticated_user => [qw( read edit attachments comment delete email_in email_out                      )],
    guest              => [                                                                                  ],
  },
  'public-read-only' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw( read                                                                         )],
    authenticated_user => [qw( read                                                                         )],
    guest              => [qw( read                                                                         )],
  },
  'public-comment-only' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw( read                  comment                                                )],
    authenticated_user => [qw( read                  comment                                                )],
    guest              => [qw( read                  comment                                                )],
  },
  'public-join-to-edit' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock           )],
    member             => [qw( read edit attachments comment delete email_in email_out                                )],
    account_user       => [qw( read                                                                         self_join )],
    authenticated_user => [qw( read                                                                         self_join )],
    guest              => [qw( read                                                                         self_join )],
  },
  'self-join' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock           )],
    member             => [qw( read edit attachments comment delete email_in email_out                                )],
    account_user       => [qw( read                                                                         self_join )],
    authenticated_user => [                                                                                            ],
    guest              => [                                                                                            ],
  },
  'intranet' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock )],
    member             => [qw( read edit attachments comment delete email_in email_out                      )],
    account_user       => [qw( read edit attachments comment delete email_in email_out                      )],
    authenticated_user => [qw( read edit attachments comment delete email_in email_out                      )],
    guest              => [qw( read edit attachments comment delete email_in email_out                      )],
  },
);

our %DeprecatedPermissionSets = (
  'public-authenticate-to-edit' => {
    admin              => [qw( read edit attachments comment delete email_in email_out admin_workspace lock               )],
    member             => [qw( read edit attachments comment delete email_in email_out                                    )],
    account_user       => [                                                                                                ],
    authenticated_user => [qw( read edit attachments comment delete email_in email_out                                    )],
    guest              => [qw( read                                                                         edit_controls )],
  },
);

# Impersonators should be able to do everything members can do, plus
# impersonate.
$_->{impersonator} = [ 'impersonate', @{ $_->{member} } ]
    for (values %PermissionSets, values %DeprecatedPermissionSets);

# Affilates (deprecated role) are permission-less
$_->{affiliate} = []
    for (values %PermissionSets, values %DeprecatedPermissionSets);

my @PermissionSetsLocalize = (loc('acl.public'), loc('acl.member-only'), loc('acl.authenticated-user-only'), loc('acl.public-read-only'), loc('acl.public-comment-only'), loc('acl.public-authenticate-to-edit') ,loc('acl.public-join-to-edit'), loc('acl.intranet'));

sub IsValidRole {
    my $class = shift;
    my $role  = shift;
    return $AllowableRoles{ $role->name };
}

sub new {
    my $class = shift;
    my %opts = @_;
    my $self = { %opts };
    bless $self, $class;
    return $self;
}

{
    Readonly my $spec => {
        set_name => SCALAR_TYPE,
        allow_deprecated => BOOLEAN_TYPE(default => 0),
    };
    sub set {
        my ($self,@args) = @_;
        sql_txn { $self->_set_permissions(@args) };
        Socialtext::Cache->clear('ws_perms');
    }

    sub _set_permissions {
        my $self = shift;
        my %p = validate( @_, $spec );
        my $wksp = $self->{wksp};

        my $workspace_id = $wksp->workspace_id;
        my %valid_sets = $p{allow_deprecated} == 0
            ? %PermissionSets
            : (%PermissionSets, %DeprecatedPermissionSets);

        my $set = $valid_sets{ $p{set_name} };
        die "Set $p{set_name} is not valid" unless $set;

        # We need to preserve the guest's email_in permission
        my $guest_id    = Socialtext::Role->Guest()->role_id();
        my $email_in_id = ST_EMAIL_IN_PERM->permission_id();
        my $sth = sql_execute(<<EOSQL, $workspace_id, $guest_id, $email_in_id);
SELECT role_id, permission_id FROM "WorkspaceRolePermission"
    WHERE workspace_id = ?
      AND role_id = ?
      AND permission_id = ?
EOSQL
        my $perms_to_keep = $sth->fetchall_arrayref->[0];

        # Delete the old permissions, and count how many we deleted
        my $dbh = Socialtext::SQL::get_dbh();
        $sth = $dbh->prepare(<<EOSQL);
DELETE FROM "WorkspaceRolePermission"
    WHERE workspace_id = ?
EOSQL
        my $rv = $sth->execute($workspace_id);
        my $has_existing_perms = $rv ne '0E0';

        # Add the new permissions
        my @new_perms = $perms_to_keep ? ($perms_to_keep) : ();
        for my $role_name ( keys %$set ) {
            my $role = Socialtext::Role->new( name => $role_name );
            for my $perm_name ( @{ $set->{$role_name} } ) {
                next if $role_name eq 'guest' and $perm_name eq 'email_in'
                        and $has_existing_perms;

                my $perm = Socialtext::Permission->new( name => $perm_name );
                push @new_perms, [$role->role_id, $perm->permission_id];
            }
        }

        # Firehose the permissions into the database
        if (@new_perms) {
            $dbh->do('COPY "WorkspaceRolePermission" FROM STDIN');
            for my $p (@new_perms) {
                $dbh->pg_putline("$workspace_id\t$p->[0]\t$p->[1]\n");
            }
            $dbh->pg_endcopy;
        }

        my $html_wafl = ( $p{set_name} =~ /^(member|intranet|public\-read|self\-join)/ ) ? 1 : 0;
        my $email_addresses = ( $p{set_name} =~ /^(member|intranet|self\-join)/ ) ? 0 : 1 ;
        my $email_notify = ( $p{set_name} =~ /^public/ ) ? 0 : 1;
        my $homepage = ( $p{set_name} eq 'member-only' ) ? 1 : 0;
        $wksp->update(
            allows_html_wafl           => $html_wafl,
            email_notify_is_enabled    => $email_notify,
            email_addresses_are_hidden => $email_addresses,
            homepage_is_dashboard      => $homepage,
        );
    }
}

{
    # This is just caching to make current_set_name run at a
    # reasonable speed.
    my %SetsAsStrings = (
        ( map { $_ => _perm_set_as_string( $PermissionSets{$_} ) }
          keys %PermissionSets
        ),
        ( map { $_ => _perm_set_as_string( $DeprecatedPermissionSets{$_} ) }
          keys %DeprecatedPermissionSets
        ) );
    sub current_set {
        my $self = shift;
        my $perms_with_roles = $self->permissions_with_roles();

        my %set;
        while ( my $pair = $perms_with_roles->next ) {
            my ( $perm, $role ) = @$pair;
            push @{ $set{ $role->name() } }, $perm->name();
        }

        # We need the contents of %set to match our pre-defined sets,
        # which assign an empty arrayref for a role when it has no
        # permissions (see authenticated-user-only).
        my $roles = Socialtext::Role->All();
        while ( my $role = $roles->next() ) {
            next unless $AllowableRoles{$role->name};
            $set{ $role->name() } ||= [];
        }

        return %set;
    }

    sub current_set_name {
        my $self = shift;

        my %set = $self->current_set;
        my $set_string = _perm_set_as_string( \%set );
        for my $name ( keys %SetsAsStrings ) {
            return $name if $SetsAsStrings{$name} eq $set_string;
        }

        return 'custom';
    }

    my %display_names = (
        'member-only' => __('wiki.acl-private'),
        'self-join'   => __('wiki.acl-self-join'),
        'custom'      => __('wiki.acl-custom'),
    );
    sub current_set_display_name {
        my $self = shift;

        my $display_name = $display_names{$self->current_set_name};
        return $display_name || __('wiki.acl-public');
    }

    sub _perm_set_as_string {
        my $set = shift;

        my @parts;
        # This particular string dumps nicely, the newlines are not
        # special or anything.
        for my $role ( sort keys %$set ) {
            my $string = "$role: ";
            # We explicitly ignore the email_in permission as applied
            # to guests when determining the set string so that it
            # does not affect the calculated set name for a
            # workspace. See RT 21831.
            my @perms = sort @{ $set->{$role} };
            @perms = grep { $_ ne 'email_in' } @perms
                if $role eq 'guest';

            $string .= join ', ', @perms;

            push @parts, $string;
        }

        return join "\n", @parts;
    }
}


{
    Readonly my $spec => {
        permission => PERMISSION_TYPE,
        role       => ROLE_TYPE,
    };
    sub add {
        my $self = shift;
        my $wksp = $self->{wksp};
        my %p = validate( @_, $spec );

        if ($p{permission}->name() eq  "self_join") {
            $self->remove(
                permission => ST_EDIT_CONTROLS_PERM, 
                role => $p{role}
            );
        }
        eval {
            sql_execute('INSERT INTO "WorkspaceRolePermission" VALUES (?,?,?)',
                $wksp->workspace_id, $p{role}->role_id,
                $p{permission}->permission_id);
        };
        if ($@ and $@ !~ m/duplicate key/) {
            die $@;
        }
        Socialtext::Cache->clear('ws_perms');
    }

    sub remove {
        my $self = shift;
        my $wksp = $self->{wksp};
        my %p = validate( @_, $spec );

        sql_execute(<<EOSQL,
DELETE FROM "WorkspaceRolePermission"
    WHERE workspace_id = ?
      AND role_id = ?
      AND permission_id = ?
EOSQL
            $wksp->workspace_id, $p{role}->role_id,
            $p{permission}->permission_id);
        Socialtext::Cache->clear('ws_perms');
    }

    sub role_can {
        my $self = shift;
        my $wksp = $self->{wksp};
        my %p = validate( @_, $spec );

        my $wksp_id = $wksp->workspace_id;
        my $role_id = $p{role}->role_id;
        my $perm_id = $p{permission}->permission_id;

        my $cache_string = $wksp_id;
        my $cached_perms = $self->cache->get($cache_string);
        return $cached_perms->{$role_id}{$perm_id} ? 1 : 0 if defined $cached_perms;

        my $sth = sql_execute(<<EOSQL, $wksp_id);
SELECT role_id, permission_id FROM "WorkspaceRolePermission"
    WHERE workspace_id = ?
EOSQL

        my %perms;
        for my $row (@{ $sth->fetchall_arrayref }) {
            $perms{$row->[0]}{$row->[1]}++;
        }

        $self->cache->set($cache_string => \%perms);
        return $perms{$role_id}{$perm_id} ? 1 : 0;
    }
}

{
    Readonly my $spec => {
        role => ROLE_TYPE,
    };
    sub permissions_for_role {
        my $self = shift;
        my $wksp = $self->{wksp};

        my %p = validate( @_, $spec );

        my $sth = sql_execute(<<EOSQL, $wksp->workspace_id, $p{role}->role_id );
SELECT permission_id
    FROM "WorkspaceRolePermission"
    WHERE workspace_id=? AND role_id=?
EOSQL

        return Socialtext::MultiCursor->new(
            iterables => [ $sth->fetchall_arrayref ],
            apply     => sub {
                my $row = shift;
                return Socialtext::Permission->new(
                    permission_id => $row->[0] );
            }
        );
    }
}

sub permissions_with_roles {
    my $self = shift;
    my $wksp = $self->{wksp};

    my $sth = sql_execute(<<EOSQL, $wksp->workspace_id);
SELECT permission_id, role_id
    FROM "WorkspaceRolePermission"
    WHERE workspace_id = ?
EOSQL

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref ],
        apply     => sub {
            my $row = shift;
            my $permission_id = $row->[0];
            my $role_id = $row->[1];

            return undef unless defined $permission_id;
            return [
                Socialtext::Permission->new( permission_id => $permission_id ),
                Socialtext::Role->new( role_id             => $role_id )
            ];
        }
    );
}

{
    Readonly my $spec => {
        user       => USER_TYPE,
        permission => PERMISSION_TYPE,
    };
    sub user_can {
        my $self = shift;
        my %p    = validate(@_, $spec);
        my $user = $p{user};
        my $perm = $p{permission};
        my $ws   = $self->{wksp};

        # get the list of Roles this User has in the WS, falling back to a
        # default Role if the User has no explicit Role in the WS
        my @roles = $ws->role_for_user($user);
        unless (@roles) {
            @roles = $user->is_authenticated && $ws->account->has_user($user)
                ? Socialtext::Role->AccountUser()
                : $user->default_role;
        }

        # check if any of those Roles have the specified Permission
        my $has_permission = first {
            $self->role_can(
                role       => $_,
                permission => $perm,
            );
            }
            @roles;
        return $has_permission ? 1 : 0;
    }
}

sub is_public {
    my $self = shift;

    return $self->role_can(
        role       => Socialtext::Role->Guest(),
        permission => ST_READ_PERM,
    );
}

sub SetNameIsValid {
    my $class = shift;
    my $name  = shift;

    return $PermissionSets{$name} ? 1 : 0;
}

sub cache { Socialtext::Cache->cache('ws_perms') }

1;

__END__

=head1 NAME

Socialtext::Workspace::Permissions - An object to query/manipulate workspace permissions.

=head2 $workspace_permissions->set( set_name => $name )

Given a permission-set name, this method sets the workspace's
permissions according to the definition of that set.

The valid set names and the permissions they give are shown below.
Additionally, all permission sets give the same permissions as C<member> plus
C<impersonate> to the C<impersonator> role.

=over 4

=item * public

=over 8

=item o guest - read, edit, comment

=item o authenticated_user - read, edit, comment, email_in

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * member-only

=over 8

=item o guest - none

=item o authenticated_user - email_in

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * authenticated-user-only

=over 8

=item o guest - none

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * public-read-only

=over 8

=item o guest - read

=item o authenticated_user - read

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * public-comment-only

=over 8

=item o guest - read, comment

=item o authenticated_user - read, comment

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * public-authenticate-to-edit ( Deprecated, do not use. )

=over 8

=item o guest - read, edit_controls

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * public-join-to-edit

=over 8

=item o guest - read, self_join

=item o authenticated_user - read, self_join

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=item * intranet

=over 8

=item o guest - read, edit, attachments, comment, delete, email_in, email_out

=item o authenticated_user - read, edit, attachments, comment, delete, email_in, email_out

=item o member - read, edit, attachments, comment, delete, email_in, email_out

=item o admin - read, edit, attachments, comment, delete, email_in, email_out, lock

=back

=back

Additionally, when a name that starts with public is given, this
method will also change allows_html_wafl and email_notify_is_enabled
to false.

=head2 $workspace_permissions->role_can( permission => $perm, role => $role );

Returns a boolean indicating whether the specified role has the given
permission.

=head2 $workspace_permissions->current_set()

Returns the workspace's current permission set as a hash.

=head2 $workspace_permissions->current_set_name()

Returns the name of the workspace's current permission set. If it does
not match any of the pre-defined sets this method returns "custom".

=head2 $workspace_permissions->add( permission => $perm, role => $role );

This methods adds the given permission for the specified role.

=head2 $workspace_permissions->remove( permission => $perm, role => $role );

This methods removes the given permission for the specified role.

=head2 $workspace_permissions->permissions_for_role( role => $role );

Returns a cursor of C<Socialtext::Permission> objects indicating what
permissions the specified role has in this workspace.

=head2 $workspace_permissions->permissions_with_roles

Returns a cursor of C<Socialtext::Permission> and C<Socialtext::Role>
objects indicating the permissions for each role in the workspace.

=head2 $workspace_permissions->is_public()

This returns true if guests have the "read" permission for the workspace.

=head2 Socialtext::Workspace::Permissions->SetNameIsValid($name)

Returns a boolean indicating whether or not the given set name is
valid.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=cut
