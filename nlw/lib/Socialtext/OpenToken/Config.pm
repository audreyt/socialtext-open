package Socialtext::OpenToken::Config;
# @COPYRIGHT@

use strict;
use warnings;
use Class::Field qw(field const);
use base qw(Socialtext::Config::Base);

###############################################################################
# Name our configuration file
const 'config_basename' => 'opentoken.yaml';

###############################################################################
# Fields that the config file contains
field 'challenge_uri';
field 'token_parameter' => 'opentoken';
field 'password';
field 'clock_skew' => 10;
field 'auto_provision_new_users' => 0;

###############################################################################
# Custom initialization routine
sub init {
    my $self = shift;

    # make sure we've got all of our required fields
    my @required = qw( challenge_uri password );
    $self->check_required_fields(@required);
}

1;

=head1 NAME

Socialtext::OpenToken::Config - Configuration object for OpenToken Authentication

=head1 SYNOPSIS

  # please refer to Socialtext::Base::Config

=head1 DESCRIPTION

C<Socialtext::OpenToken::Config> encapsulates all of the information necessary
to configure the OpenToken adapter for Socialtext.

OpenToken configuration objects can either be loaded from YAML files or
created from a has of configuration values:

=over

=item B<challenge_uri> (required)

An absolute URI to the OpenToken Service Provider, which kickstarts an
SP-initiated SAML Assertion.

=item B<token_parameter>

The name of the form parameter which contains the OpenToken when it is POSTed
back to use from the SP.  Defaults to "opentoken".

=item B<password> (required)

The shared password used for decrypting the OpenTokens, Base64 encoded.

=item B<clock_skew>

Number of seconds to allow for clock skew when validating OpenTokens.
Defaults to 10 seconds.

=item B<auto_provision_new_users>

Specifies whether or not new Users should be automatically provisioned on the
Socialtext Appliance.  Defaults to "0" (no).  Set to a non-zero value to
enable auto-provisioning of Users.

=back

=head1 METHODS

The following methods are specific to C<Socialtext::OpenToken::Config>
objects.  For more information on other methods that are available, please
refer to L<Socialtext::Base::Config>.

=over

=item B<$self-E<gt>init()>

Custom initialization routine.  Verifies that the configuration contains all
of the required fields.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Config::Base>.

=cut
