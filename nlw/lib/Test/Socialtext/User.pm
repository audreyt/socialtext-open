package Test::Socialtext::User;
# @COPYRIGHT@

use strict;
use warnings;
use Carp qw(croak);
use Class::Field qw(const);
use Guard qw(guard);
use List::MoreUtils qw(any);

const 'test_username'      => 'devnull1@socialtext.com';
const 'test_email_address' => 'devnull1@socialtext.com';
const 'test_password'      => 'd3vnu11l';

sub delete_recklessly {
    my ($class, $maybe_user) = @_;

    # Load classes on demand
    require Socialtext::SQL;
    require Socialtext::User;

    # Get a hold of the System User record
    my $system_user = Socialtext::User->SystemUser;

    # Get the User Id for the User (which we'll need for doing DB updates
    # below).
    #
    # DON'T instantiate a User object, though, as that may trigger other
    # behaviour (e.g. refreshing LDAP data) that may have troubles.  This *is*
    # to be run in a test environment, so trigger as little external behaviour
    # as is possible.
    my $user_id = (ref($maybe_user) && $maybe_user->can('user_id'))
        ? $maybe_user->user_id
        : $maybe_user;

    # Don't delete Guest and SystemUser
    my @req_users = ($system_user, Socialtext::User->Guest());
    if ( any { $_->user_id == $user_id } @req_users ) {
        croak "can't delete system created users, even recklessly";
    }

    # make these things "owned" by the System User
    Socialtext::SQL::sql_execute( q{
        UPDATE "Workspace"
           SET created_by_user_id = ?
         WHERE created_by_user_id = ?
        }, $system_user->user_id, $user_id);
    Socialtext::SQL::sql_execute( q{
        UPDATE page
           SET creator_id = ?
         WHERE creator_id = ?
        }, $system_user->user_id, $user_id);
    Socialtext::SQL::sql_execute( q{
        UPDATE page_revision
           SET editor_id = ?
         WHERE editor_id = ?
        }, $system_user->user_id, $user_id);
    Socialtext::SQL::sql_execute( q{
        UPDATE page
           SET last_editor_id = ?
         WHERE last_editor_id = ?
        }, $system_user->user_id, $user_id);
    Socialtext::SQL::sql_execute( q{
        UPDATE page
           SET creator_id = ?
         WHERE creator_id = ?
        }, $system_user->user_id, $user_id);

    # Delete things owned/associated with this user
    Socialtext::SQL::sql_execute(
        q{DELETE FROM signal WHERE user_id = ?}, $user_id);
    Socialtext::SQL::sql_execute(
        q{DELETE FROM attachment WHERE creator_id = ?}, $user_id);
    Socialtext::SQL::sql_execute(
        q{DELETE FROM signal_thread_tag WHERE user_id = ?}, $user_id);

    # Delete the User from the DB, and let this cascade across all other DB
    # tables, nuking data from the DB as it goes.
    Socialtext::SQL::sql_execute( q{
        DELETE FROM all_users
         WHERE user_id = ?
        }, $user_id
    );

    # Clear all caches (the User, and anything that may have cached a copy of
    # our count of the User)
    Socialtext::Cache->clear();
}

sub snapshot {
    my %existing = map { $_ => 1 } _get_user_ids();
    my $guard = guard {
        my @eventual = _get_user_ids();
        foreach my $user_id (@eventual) {
            unless ($existing{$user_id}) {
                Test::Socialtext::User->delete_recklessly($user_id);
            }
        }
    };
    return $guard;
}

sub _get_user_ids {
    require Socialtext::SQL;
    my $rows = Socialtext::SQL::get_dbh()->selectall_arrayref( qq{
        SELECT user_id FROM all_users ORDER BY user_id;
    } );
    return map { $_->[0] } @{$rows};
}

1;

=head1 NAME

Test::Socialtext::User - methods to operate on Users from within tests

=head1 SYNOPSIS

  use Test::Socialtext::User;

  # recklessly delete a User from the DB
  $user = Socialtext::User->new(username => $username);
  Test::Socialtext::User->delete_recklessly($user);

  # or...
  $homunculus = ...
  Test::Socialtext::User->delete_recklessly($homunculus);

  # or...
  Test::Socialtext::User->delete_recklessly($user_id);

  # create guard, to auto-cleanup Users at end of scope
  $guard = Test::Socialtext::User->snapshot();

=head1 DESCRIPTION

C<Test::Socialtext::User> implements methods that can be used to operate on
C<Socialtext::User> objects from within test suites.

These methods are placed here so that its B<really> obvious that you don't
want to be using these methods as part of the regular operation of the system.
They're useful for test purposes, but beyond that you should keep your fingers
out of them.

=head1 METHODS

=head2 B<Test::Socialtext::User-E<gt>delete_recklessly($maybe_user)>

Deletes the User record for the specified C<$maybe_user> outright, purging
B<all> of the data related to this User from the DB.  This is an
B<irreverible> action!

This method accepts a C<user_id>, a C<Socialtext::User> object, or a
homunculus object.  I<Any> of these will cause the deletion of data relating
to this User.

Workspaces and Pages that this User had created are first re-assigned to be
owned by the System User, so that we don't cascade through a series of deletes
in the DB that leaves the system in a funky state; you'd have files for the
Workspace/Pages on disk but no records for them in the DB.

=head2 B<Test::Socialtext::User-E<gt>snapshot()>

Returns a C<Guard> object which will automatically call C<delete_recklessly()>
for any Users that didn't exist in the system at the moment where the Guard
was created.

B<Really> useful for tests; create the guard, do your stuff, and when the
guard goes out of scope it'll automatically purge any User records that you
created during the test.

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

=cut
