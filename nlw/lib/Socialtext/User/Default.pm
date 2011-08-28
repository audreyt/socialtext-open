package Socialtext::User::Default;
# @COPYRIGHT@
use Moose;
our $VERSION = '0.03';
use Socialtext::String;
use DateTime::Infinite;
use Digest::SHA;
use Encode;
use namespace::clean -except => 'meta';

BEGIN { extends 'Socialtext::User::Base' }

has '+cached_at' => (builder => '_build_cached_at', lazy => 1);

sub _build_cached_at {
    return DateTime::Infinite::Future->new;
}

sub update {
    my ($self, %p) = @_;
    my $factory = $self->factory();
    return $factory->update( $self, %p );
}

sub has_valid_password {
    return 1 if shift->password ne '*none*';
}

sub password_is_correct {
    my $self = shift;
    my $pw   = shift;
    return $self->_verify_password( $pw, $self->password );
}

# Helper methods
sub _verify_password {
    my $self     = shift;
    my $pw       = shift;
    my $db_pw    = shift;

    $pw = Socialtext::String::trim($pw);

    if (length $db_pw == 13) {
        # Legacy password using crypt()
        return $self->_crypt( $pw, $db_pw ) eq $db_pw;
    }
    else {
        # Modern password using hmac_sha256_hex()
        return $self->_sha256( $pw, $db_pw ) eq $db_pw;
    }
}

sub _encode_password {
    my $self = shift;
    my $pw   = shift;

    return $self->_sha256($pw, time());
}

sub _crypt {
    shift;
    my $pw   = shift;
    my $salt = shift;

    # Avoid double-encoding -- only encode_utf8 if $pw is not octets already.
    $pw = Encode::encode_utf8($pw) if Encode::is_utf8($pw);

    return crypt( $pw, $salt );
}

sub _sha256 {
    shift;
    my $pw   = shift;
    my $salt = shift;

    # Use the text before the first : as the salt.
    $salt =~ s/:.*//s;

    $pw = Encode::encode_utf8($pw) if Encode::is_utf8($pw);
    my $sha256 = Digest::SHA::hmac_sha256_hex($pw, $salt);

    return "$salt:SHA256:$sha256";
}

sub expire { 
    # cannot expire Default users
    return;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
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

=item B<new()>

Creates a new Default homunculus.  This method probably shouldn't be called directly; use a factory or C<Socialtext::User>'s new method.

Forces the 'cached_at' param to be infinitely far in the future, then calls C<SUPER::new>.

=item B<update(%params)>

Updates the user's information with the new key/val pairs passed in.  You
cannot change username or email_address for a row where is_system_created is
true.

This is simply a shortcut method to C<$factory-E<gt>update($self,%params)>.

=item B<has_valid_password()>

Returns true if the user has a valid password.

For now, this is defined as any password not matching "*none*".

=item B<password_is_correct($pass)>

Checks to see if the given password is correct for this user.  Returns true if
the given password is correct, false otherwise.

=item B<expire()>

Does nothing; Default users cannot be expired.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::User::Base>.

=cut
