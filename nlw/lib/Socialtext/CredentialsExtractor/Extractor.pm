package Socialtext::CredentialsExtractor::Extractor;
# @COPYRIGHT@

use Moose::Role;
use Socialtext::JSON qw(json_true json_false);
use Socialtext::User;
use Socialtext::Log qw(st_log);

# Returns the list of headers used by this Creds Extractor
requires 'uses_headers';

# Attempts to extract creds from the given set of headers
requires 'extract_credentials';

# Logging helper
sub log {
    my $class = shift;
    my $level = shift;
    my $mesg  = shift;

    $class =~ s/.*:://;     # short class-name
    st_log($level, "$class - $mesg");
}

# Converts a "username" to a "user_id".
sub username_to_user_id {
    my $class    = shift;
    my $username = shift;
    return unless $username;

    my $user = Socialtext::User->new(username => $username);
    return $user->user_id if $user;
    return;
}

# Returns "valid" response.
sub valid_creds {
    my $class = shift;
    my %extra = @_;
    return {
        valid         => json_true(),
        needs_renewal => json_false(),
        %extra,
    };
}

# Returns "invalid" response.
sub invalid_creds {
    my $class  = shift;
    my %extra  = @_;
    my $reason = $extra{reason};
    $class->log('warning', "invalid credentials - $reason") if ($reason);
    return {
        valid => json_false(),
        %extra,
    };
}

no Moose::Role;

1;

=head1 NAME

Socialtext::CredentialsExtractor::Extractor - Base role for credentials extractors

=head1 SYNOPSIS

  use Moose;
  with 'Socialtext::CredentialsExtractor::Extractor';

  sub uses_headers {
      # ...
  }

  sub extract_credentials {
      # ...
  }

  1;

=head1 DESCRIPTION

This module defines a base role to be consumed by all Credential Extractors.

This role requires that the Creds Extractors:

=over

=item *

Explicitly state which inbound HTTP headers they require in order to extract
credentials (C<uses_headers()>).

This method (C<uses_headers()>) takes no parameters, and is expected to return
a list of all of the HTTP Headers that are needed by the Credentials
Extractor.

=item *

Provide a method that can extract the credentials from the provided inbound
HTTP headers (C<extract_credentials()>).

The HTTP headers provided are encoded such that:

=over

=item *

Keys are in all upper-case letters, and all "-" have been converted to "_".
(e.g. "Content-Type" becomes "CONTENT_TYPE").

=item *

Headers occurring multiple times have been flattened into a single line, with
multiple values separated by ";".

=back

This method (C<extract_credentials()>) takes a single parameter; a hash-ref of
inbound HTTP headers, and is expected to return the C<user_id> of the logged
in User (or void/undef if we are unable to extract credentials).

=back

=cut
