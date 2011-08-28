# @COPYRIGHT@
package Socialtext::Data;

use strict;
use warnings;

sub Classes {
    return map { 'Socialtext::' . $_ }
           qw( Account
               UserMetadata
               Workspace
               Pluggable::Adapter
             );
}

sub humanize_column_name {
    my $field = shift;

    return join ' ', split /_/, lc $field;
}

1;

__END__

=head1 NAME

Socialtext::Data - Documentation and functions about Socialtext data objects

=head1 DESCRIPTION

This module contains a few functions for use by the various Socialtext
data classes, but it primarily exists to document the DBMS schema.

=head1 FUNCTIONS

The C<Socialtext::Data> namespace contains the following functions:

=head2 Socialtext::Data::Classes()

This method returns the full name of each data object class. It I<does
not> load these classes.

=head2 Socialtext::Data::humanize_column_name($name)

Returns a more human-readable version of a column name, so
"email_address" becomes "email address".

=head1 Schema

See https://www.socialtext.net/dev-guide/index.cgi?schemadiagram for a
picture of the schema.

The schema currently holds the data about users, workspaces, ACLs, and
accounts. In the future, more data will be moved into this table.

=head2 Tables

Whenever a table has a single column primary key, like user_id for the
User table, the column is sequenced, and a new value is automatically
generated when inserting a new row.

The schema currently contains the following tables:

=over 4

=item * user

This table contains information about the user.  In many cases, the
username and email_address are the same, but it is quite common
for this to I<not> be the case (e.g. when doing LDAP or SSO
integration, where the customer may have configured the "username" to
be their "sAMAccountName" [or equivalent]).

All users should have a creator user, except for the "System User".

There are two users which must be present in all systems, the "System
User" and "Guest User". The former is used as a default when the
current user cannot be determined, for example when creating a
workspace from the command line. The latter is used as the default
user when a client who is not logged in visits a workspace.

For these special users, the users.is_system_created column is true,
and for all others it is false.

These two users cannot be made a member of any workspaces.

Note that user preferences are still stored on the file system.

=item * Workspace

This contains the workspace name, title, and various per-workspace
settings. The name column is a candidate key.

Each workspace belongs to one account. The default account for a
workspace is "Unknown", but when a workspace is created from an
existing workspace, it "inherits" that workspace's account.

Every workspace has a creator user.

=item * WorkspacePingURI

This table stores zero or more ping URIs per workspace. If a workspace
has URIs, then blog pings are sent on each page save. See
L<Socialtext::WeblogUpdates> for more details.

=item * Account

An account is basically a named collection of workspaces, and is used
for the purposes of billing. The name column is a candidate key.

There are two accounts which must be present on all systems, "Unknown"
and "Socialtext".

The Unknown account will be used when importing existing data, but
once it is removed from all existing workspaces, it should no longer
be used.

The Socialtext account is used for workspaces that are created by the
application, such as "help", or for workspaces that are for our
company use, such as "corp".

=item * Permission

This table is just a list of valid permission names. The name column
is a candidate key.

All of the valid permission must be present in the DBMS for the
application to function.

=item * Role

This table is just a list of valid role names. There are only four
roles, "guest", "authenticated_user" "member", and "admin".
The name column is a candidate key.

The first two roles are "default roles", which means that are used in
absence of an explicit role assignment. They cannot be explicitly
assigned to a User.

All of these roles must be present in the DBMS for the application to
function.

Note that business and technical admin privileges are granted through
the "User.is_business_admin" and "User.is_technical_admin" columns,
not through a role.

=item * WorkspaceRolePermission

This defines what permissions a role has for a workspace.

This table is how we define different workspace types. For example, in
a normal private, members-only workspace guest user have no
permissions except for "email_in". In a public workspace, guests have
a number of permissions including "read", "edit", etc.

The `Socialtext::Workspace` contains a number of named permission sets
such as "public", "member-only", "public-comment-only", and so
on. However, this class also provides an API for finer-grained
manipulation of the permissions for a role.

=item * sessions

This table is used for storing session data in the DBMS, and is not
related to any other table in the schema.

=back

=head2 Schema Notes

It is possible to join the User Set and WorkspaceRolePermission tables on
workspace_id and role_id (togther), but they are not actually related via a
foreign key. This join allows for a single query to determine if a user has a
specific permission in a workspace.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut
