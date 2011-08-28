package Socialtext::NTLM::Config;
# @COPYRIGHT@

use strict;
use warnings;
use Class::Field qw(field const);
use base qw(Socialtext::Config::Base);

###############################################################################
# Name our configuration file
const 'config_basename' => 'ntlm.yaml';

###############################################################################
# Fields that the config file contains
field 'domain';
field 'primary';
field 'backup' => [];
field 'handshake_timeout' => 2.0;

###############################################################################
# Custom initialization routine
sub init {
    my $self = shift;

    # make sure we've got all of our required fields
    my @required = (qw( domain primary ));
    $self->check_required_fields(@required);

    # "backup" should *always* be treated as a list-ref
    my $backup = $self->backup();
    if ($backup and not ref($backup)) {
        $self->backup( [$backup] );
    }
}

###############################################################################
# Helper method, returning the name of the *default* NTLM domain to use.
sub DefaultDomain {
    my $class   = shift;
    my @configs = $class->load();
    my $default = $configs[0];
    return unless $default;
    return $default->domain();
}

###############################################################################
# Helper method, returning the name of the *fallback* NTLM domain to use.
sub FallbackDomain {
    my $class   = shift;
    my @configs = $class->load();
    my $default = $configs[1];
    return unless $default;
    return $default->domain();
}

sub ConfigureApacheAuthenNTLM {
    my $class = shift;
    my $o = shift;

    # force Apache::AuthenNTLM to split up the "domain\username" and only
    # leave us the "username" part; our Authen system doesn't understand
    # composite usernames and isn't able to handle this as an exception to the
    # rule.
    $o->{splitdomainprefix} = 1;

    # read in our NTLM config, and set up our PDC/BDCs
    my @all_configs = $class->load();
    foreach my $config (@all_configs) {
        my $domain  = lc( $config->domain() );
        my $primary = $config->primary();
        my $backups = $config->backup();

        $o->{smbpdc}{$domain} = $primary;
        $o->{smbbdc}{$domain} = join ' ', @{$backups};
    }
    
    # the default domain comes from the 0th config too:
    $o->{handshake_timeout} = 0+$all_configs[0]->handshake_timeout;

    # set the default/fallback domains, in case the NTLM handshake doesn't
    # indicate which one to use
    $o->{defaultdomain}  = $class->DefaultDomain();
    $o->{fallbackdomain} = $class->FallbackDomain();

    return $o;
}

1;

=head1 NAME

Socialtext::NTLM::Config - Configuration object for NTLM Authentication

=head1 SYNOPSIS

  # please refer to Socialtext::Base::Config

=head1 DESCRIPTION

C<Socialtext::NTLM::Config> encapsulates all of the information describing the
NTLM Domains and Domain Controllers that can be used for authentication
purposes.

NTLM configuration objects can either be loaded from YAML files or created
from a hash of configuration values:

=over

=item B<domain> (required)

The name of the NT Domain.

=item B<primary> (required)

The name of the Primary Domain Controller for the domain.

=item B<backup>

The name(s) of the Backup Domain Controllers for the domain.

=item B<handshake_timeout>

How long clients are given between type 1 and type 3 requests (the initiating
and completing HTTP requests).  Since we can only process one handshake
concurrently at a time (an NTLM+samba limitation), we need to time-out slow
handshakes.  Setting this too low will cause lots of authentication pop-ups.
Default: 2.0 seconds.

=back

=head1 METHODS

The following methods are specific to C<Socialtext::NTLM::Config> objects.
For more information on other methods that are available, please refer to
L<Socialtext::Base::Config>.

=over

=item B<$self-E<gt>init()>

Custom initialization routine.  Verifies that the configuration contains all
of the required fields, and ensures that the C<backup> field is always treated
in a list-ref context.

=item B<Socialtext::NTLM::Config-E<gt>DefaultDomain()>

Returns the name of the Default NTLM Domain that is to be used for NTLM
authentication; e.g. if no NTLM Domain was provided in the NTLM handshake,
what Domain should we attempt authentication against by default?

=item B<Socialtext::NTLM::Config-E<gt>FallbackDomain()>

Returns the name of the Fallback NTLM Domain that is to be used for NTLM
authentication; e.g. if no NTLM Domain was provided in the NTLM handshake and
its not the Default Domain, try this NTLM Domain as a second option.

=back

=head1 AUTHOR

Socialtext, Inc., C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Config::Base>.

=cut
