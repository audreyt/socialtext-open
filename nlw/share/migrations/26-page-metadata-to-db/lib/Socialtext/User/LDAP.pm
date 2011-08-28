package Socialtext::User::LDAP;
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::LDAP;
use base qw(Socialtext::User::Base);

our $VERSION = '0.03';

sub password {
    return '*no-password*';
}

sub has_valid_password {
    return 1;
}

sub password_is_correct {
    my ($self, $pass) = @_;

    # empty passwords not allowed
    return 0 unless ($pass);

    # authenticate against LDAP server
    return Socialtext::LDAP->authenticate(
        user_id  => $self->user_id(),
        password => $pass,
        ($self->driver_id() ? (driver_id=>$self->driver_id()) : ()),
    );
}

sub delete {
    # no-op; we *WON'T* go to the LDAP store and try to delete the user, but
    # we do want to let local data caches/stores get deleted.  Thus, no-op it.
}

1;

=head1 NAME

Socialtext::User::LDAP - A Socialtext LDAP User object

=head1 SYNOPSIS

  use Socialtext::User::LDAP::Factory;

  # create a default LDAP user factory
  $factory = Socialtext::User::LDAP::Factory->new();

  # use the factory to find user records
  $user = $factory->GetUser( user_id => $user_id );
  $user = $factory->GetUser( username => $username );
  $user = $factory->GetUser( email_address => $email );

  # authenticate (an already instantiated user)
  $auth_ok = $user->password_is_correct( $password );

=head1 DESCRIPTION

C<Socialtext::User::LDAP> provides an implementation for a User record that
happens to exist in an LDAP data store, which is derived from
C<Socialtext::User::Base>.

=head1 METHODS

=over

=item B<user_id()>

Returns the ID for the user, as per the attribute mapping in the LDAP
configuration.

=item B<username()>

Returns the username for the user, as per the attribute mapping in the LDAP
configuration.

=item B<email_address()>

Returns the e-mail address for the user, as per the attribute mapping in the
LDAP configuration.  If the user has multiple e-mail addresses, only the
B<first> is returned.

=item B<first_name()>

Returns the first name for the user, as per the attribute mapping in the LDAP
configuration.

=item B<last_name()>

Returns the last name for the user, as per the attribute mapping in the LDAP
configuration.

=item B<password()>

Returns '*no-password*'.

=item B<has_valid_password()>

Returns true if the user has a valid password.

=item B<password_is_correct($pass)>

Checks to see if the given password is correct for this user.  Returns true if
the given password is correct, false otherwise.

This check is performed by attempting to re-bind to the LDAP connection as the
user.

=item B<delete()>

B<DOES NOTHING.>  No-op/stub function; we do B<NOT> go delete the user from
the LDAP store.  We may, however, want to purge our local data stores of all
record of this user (thus, a no-op).

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::User::Base>.

=cut
