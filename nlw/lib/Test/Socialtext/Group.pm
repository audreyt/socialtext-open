package Test::Socialtext::Group;
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Group::Homunculus;
use Socialtext::MultiCursor;

sub All {
    my $class = shift;

    require Socialtext::SQL;

    my $sql = qq{
        SELECT *
          FROM groups
         ORDER BY driver_group_name;
    };
    my $sth = Socialtext::SQL::sql_execute($sql);

    return Socialtext::MultiCursor->new(
        iterables => [ $sth->fetchall_arrayref( {} ) ],
        apply => sub {
            my $row = shift;
            return Socialtext::Group::Homunculus->new( %{$row} );
        },
    );

    # Clear all caches (the Group, and anything that may have cached a copy of
    # our count of the Group)
    Socialtext::Cache->clear();
}

sub delete_recklessly {
    my $class       = shift;
    my $maybe_group = shift;
    my $group_id = ref($maybe_group) ? $maybe_group->group_id : $maybe_group;

    require Socialtext::SQL;

    Socialtext::SQL::sql_execute( q{
        DELETE FROM groups
         WHERE group_id = ?
    }, $group_id );

    Socialtext::SQL::disconnect_dbh();
}

1;

=head1 NAME

Test::Socialtext::Group - methods to operate on Groups from within tests

=head1 SYNOPSIS

  use Test::Socialtext::Group;

  # recklessly delete a Group from the DB
  $group = Socialtext::Group->GetGroup(group_id => $group_id);
  Test::Socialtext::Group->delete_recklessly($group);

=head1 DESCRIPTION

C<Test::Socialtext::Group> implements methods that can be used to operate on
C<Socialtext::Group> objects from within test suites.

These methods are placed here so that its B<really> obvious that you don't
want to be using these methods as part of the regular operation of the system.
They're useful for test purposes, but beyond that you should keep your fingers
out of them.

=head1 METHODS

=over

=item B<Test::Socialtext::Group-E<gt>delete_recklessly($group)>

Deletes the given C<$group> record outright, purging B<all> of the data
related to this Group from the DB.  This is an B<irreversible> action!

This method accepts either a C<Socialtext::Group> object, or a Group
homunculus object.  I<Either> of these will cause the deletion of data
relating to this Group.

=item B<Test::Socialtext::Group-E<gt>All()>

Return a C<Socialtex::MultiCursor> of C<Socialtext::Group::Homunculus>
objects. This works regardless of whether or not LDAP drivers are configured
for groups.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

=cut
