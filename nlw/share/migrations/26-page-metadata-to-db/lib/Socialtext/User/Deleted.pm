# @COPYRIGHT@
package Socialtext::User::Deleted;
use strict;
use warnings;
use base qw(Socialtext::User::Base);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{email_address} = 'deleted.user@socialtext.com';
    $self->{first_name}    = 'Deleted';
    $self->{last_name}     = 'User';
    $self->{username}    ||= 'deleted-user';
    return $self;
}

sub password {
    return '*no-password*';
}

sub has_valid_password {
    # this is a deleted user, shouldn't have a valid password any longer.
    return 0;
}

sub password_is_correct {
    # this is a deleted user, shouldn't have a password that can be validated.
    return 0;
}

sub delete {
    # no-op; can't delete a missing/incomplete user record, but we do want to
    # let the local data caches/stores get deleted.  Thus, no-op it.
}

1;

__END__

=head1 NAME

Socialtext::User::Deleted - A Socialtext user object placeholder

=head1 SYNOPSIS

  use Socialtext::User::Deleted;

  my $user = Socialtext::User::Deleted->new( user_id => $user_id );

=head1 DESCRIPTION

This class provides methods for dealing with users that can no longer
be instantiated via their canonical drivers, and is derived from
C<Socialtext::User::Base>.

=head1 METHODS

=over

=item B<Socialtext::User::Deleted-E<gt>new($data)>

Creates a new user object based on the provided C<$data> (which could be a HASH
or HASH-REF of data).

The C<$data> provided should be that from the original driver that had
jurisdiction over the user.

=item B<driver_name()>

Returns the name of the original driver that owned the deleted user.

=item B<driver_id()>

Returns the unique ID for the instance of the original driver that owned the
deleted user.

=item B<driver_key()>

Returns the fully qualified driver key ("name:id") of the original driver that
owned the deleted user.

If no unique C<driver_id> is available, this method returns the C<driver_name>
(e.g. "Default").

=item B<user_id()>

Returns the original unique user_id the deleted user had within the
driver's scope.

=item B<username()>

Returns the original username the deleted user had within the driver's scope.

=item B<email_address()>

Since we don't cache email addresses for users, we give a default
email address.

=item B<first_name()>

Returns 'Deleted'.

=item B<last_name()>

Returns 'User'.

=item B<password()>

Returns '*no-password*'.

=item B<has_valid_password()>

Returns 0; deleted Users aren't valid, so they obviously don't have a valid
password.

=item B<password_is_correct()>

Returns 0, no matter what is passed in.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::User::Base>.

=cut
