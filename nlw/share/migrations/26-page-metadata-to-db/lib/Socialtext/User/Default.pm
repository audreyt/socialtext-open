# @COPYRIGHT@
package Socialtext::User::Default;

use strict;
use warnings;

use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE ARRAYREF_TYPE WORKSPACE_TYPE );

our $VERSION = '0.02';

use Socialtext::String;
use Readonly;
use Socialtext::User;
use Socialtext::l10n qw(loc);
use base qw(Socialtext::User::Base);

sub _factory {
    # Get an instance of a Factory object for our data store
    #
    # XXX: this only works because we ONLY HAVE one "Default" factory.  Once
    #      we have multiple "Default" factories, this method will need to be
    #      reworked to grab the specific factory for this user record.
    require Socialtext::User::Default::Factory;
    return Socialtext::User::Default::Factory->new();
}

sub delete {
    my $self = shift;
    my $factory = $self->_factory();
    return $factory->delete($self);
}

sub update {
    my ($self, %p) = @_;
    my $factory = $self->_factory();
    return $factory->update( $self, %p );
}

{
    Readonly my $spec => { password => SCALAR_TYPE };
    sub ValidatePassword {
        shift;
        my %p = validate( @_, $spec );

        return ( loc("Passwords must be at least 6 characters long.") )
            unless length $p{password} >= 6;

        return;
    }
}

sub has_valid_password {
    my $self = shift;

    return 1
        if $self->password ne '*none*';
}

sub password_is_correct {
    my $self = shift;
    my $pw   = shift;

    my $db_pw = $self->password;
    my $crypt_pw = $self->_crypt( Socialtext::String::trim($pw), $db_pw );
    return $crypt_pw eq $db_pw;
}

# Helper methods
sub _crypt {
    shift;
    my $pw   = shift;
    my $salt = shift;

    # Avoid double-encoding -- only encode_utf8 if $pw is not octets already.
    $pw = Encode::encode_utf8($pw) if Encode::is_utf8($pw);

    return crypt( $pw, $salt );
}

1;

__END__

=head1 NAME

Socialtext::User::Default - A Socialtext RDBMS User object

=head1 SYNOPSIS

  use Socialtext::User::Default::Factory;

  # create default a user factory
  $factory = Socialtext::User::Default::Factory->new();

  # use the factory to find user records
  $user = $factory->GetUser( user_id => $user_id );
  $user = $factory->GetUser( username => $username );
  $user = $factory->GetUser( email_address => $email_address );

  # authenticate (an already instantiated user)
  $auth_ok = $user->password_is_correct( $password );

=head1 DESCRIPTION

C<Socialtext::User::Default> provides an implementation for a User record that
happens to exist in our DBMS data store, derived from C<Socialtext::User::Base>.

=head1 METHODS

=over

=item B<delete()>

Deletes the user from the data store.

This is simply a shortcut method to C<$factory-E<gt>delete($self)>.

=item B<update(%params)>

Updates the user's information with the new key/val pairs passed in.  You
cannot change username or email_address for a row where is_system_created is
true.

This is simply a shortcut method to C<$factory-E<gt>update($self,%params)>.

=item B<Socialtext::User::Default::Factory-E<gt>ValidatePassword(password=E<gt>$pw)>

Given a password, this returns a list of error messages if the password is
invalid.

=item B<has_valid_password()>

Returns true if the user has a valid password.

For now, this is defined as any password not matching "*none*".

=item B<password_is_correct($pass)>

Checks to see if the given password is correct for this user.  Returns true if
the given password is correct, false otherwise.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::User::Base>.

=cut
