# @COPYRIGHT@
package Socialtext::CredentialsExtractor;
use strict;
use warnings;
use List::MoreUtils qw(uniq);

use Socialtext::AppConfig;
use Socialtext::Timer qw/time_scope/;
use base qw( Socialtext::MultiPlugin );

sub base_package {
    return 'Socialtext::CredentialsExtractor::Extractor';
}

our %driver_aliases = (
    Apache => 'RemoteUser',     # should've had this name in the first place
);

sub _drivers {
    my $class = shift;
    my $drivers = Socialtext::AppConfig->credentials_extractors();
    my @drivers =
        map { $driver_aliases{$_} || $_ }
        split /:/, $drivers;
    return @drivers;
}

sub ExtractCredentials {
    my $class = shift;
    my $hdrs  = shift;
    my $t = time_scope 'extract_credentials';
    return $class->_first('extract_credentials', $hdrs);
}

sub _key {
    my $key = shift;
    $key =~ tr/-/_/;
    return uc($key);
}

sub HeadersNeeded {
    my $class = shift;
    return uniq $class->_aggregate('uses_headers');
}

1;

__END__

=head1 NAME

Socialtext::CredentialsExtractor - a pluggable mechanism for extracting
credentials from a Request

=head1 SYNOPSIS

  use Socialtext::CredentialsExtractor;

  my $creds = Socialtext::CredentialsExtractor->ExtractCredentials($headers);

  die "No creds, can't do anything" unless ($creds->{valid});

=head1 DESCRIPTION

This class provides a hook point for registering new means of gathering
credentials from a hash-ref of HTTP headers and Environment Variables.

=head1 METHODS

=head2 Socialtext::CredentialsExtractor->ExtractCredentials($headers)

Processes the provided hash-ref of C<$headers> with the list of configured
Credentials Extractors (see L<Socialtext::AppConfig>), and returns a data
structure outlining the validity of the credentials found:

  {
      valid: 1,         # true/false; are the creds valid?
      valid_for: 60,    # seconds that these creds can be considered valid
      user_id: 123,     # User Id of verified User
      needs_renewal: 0, # true/false; should creds be re-verified ?
  }

The provided hash-ref of C<$headers> is to be encoded such that:

=over

=item *

Header names are transformed such that they're in all upper-case, and such
that all "-" characters are replaced with "_".

=item *

Header values are flattened into a single line,

=item *

Multiple values are separated by a ";".

=back

=head2 base_package()

Base package underneath which all Credentials Extractor plugins are to be
found.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut
