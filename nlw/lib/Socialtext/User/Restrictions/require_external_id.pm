package Socialtext::User::Restrictions::require_external_id;

use Moose;
with 'Socialtext::User::Restrictions::base';

sub _restriction_type { 'require_external_id' };

sub send {
    my $self = shift;
    my $user = $self->user;

    # Forcably remove any existing external id for the User
    if (defined $user->private_external_id) {
        $user->update_private_external_id(undef);
    }
}

sub confirm {
    # no notification to send; no-op
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Socialtext::User::Restrictions::require_external_id - External Id restriction

=head1 SYNOPSIS

  use Socialtext::User::Restrictions::require_external_id

  # require that a User confirm their e-mail address
  my $restriction = Socialtext::User::Restrictions::require_external_id->CreateOrReplace( {
      user_id => $user->user_id,
  } );

  # clear any existing External Id for the User, and let them know that they
  # need to provide one.
  $restriction->send;

  # send any confirmation messages necessary to indicate that the External Id
  # has been provided.
  $restriction->confirm;

  # clear the Restriction (after the User provided an External Id)
  $restriction->clear;

=head1 DESCRIPTION

This module implements a Restriction requiring the User to provide an External
Id for their User record.

=head1 METHODS

=over

=item $self->send()

Removes any existing External Id for the User.

=item $self->confirm()

Sends out all of the notifications necessary, once the User has provided an
External Id.

=back

=head1 COPYRIGHT

Copyright 2011 Socialtext, Inc., All Rights Reserved.

=cut
