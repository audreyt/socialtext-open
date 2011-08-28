package Socialtext::URI;
#@COPYRIGHT@

use strict;
use warnings;

use Socialtext::AppConfig;
use Socialtext::HTTP::Ports;
use URI::FromHash;
use Socialtext::Cache;

# Default scheme, which *is* over-ridden by at least one module (ST::CLI)
our $default_scheme = 'http';

sub uri {
    # Optimize for the common case: Socialtext::URI::uri(path => ...).
    if (@_ == 2 and $_[0] eq 'path') {
        # We assume that _scheme_host_port() won't change during a request.
        my $cache = Socialtext::Cache->cache('uri_path');
        my $uri = $cache->get('');

        if (!$uri) {
            $uri = URI::FromHash::uri_object( _scheme_host_port() );
            $cache->set('' => $uri);
        }

        $uri->path($_[1]);
        return $uri->as_string;
    }

    URI::FromHash::uri( _scheme_host_port(), @_ );
}

sub uri_object {
    URI::FromHash::uri_object( _scheme_host_port(), @_ );
}

sub _scheme_host_port {
    my $scheme = _scheme();
    return (
        scheme => $scheme,
        host   => Socialtext::AppConfig->web_hostname(),
        (($scheme eq 'http') ? _http_port() : _https_port())
    );
}

sub _scheme {
    if (Socialtext::AppConfig->ssl_only or Socialtext::AppConfig->prefer_https) {
        # If SSL-only is enabled, *only* generate HTTPS URIs (regardless of how
        # we're connected to the system).
        return ( scheme => 'https' );
    }
    elsif ($ENV{NLWHTTPSRedirect}) {
        return ( scheme => 'https' );
    }
    else {
        return ( scheme => $default_scheme );
    }
}

sub _http_port {
    my $port = Socialtext::HTTP::Ports->http_port();
    return () if ($port == Socialtext::HTTP::Ports->STANDARD_HTTP_PORT());
    return (port => $port);
}

sub _https_port {
    my $port = Socialtext::HTTP::Ports->https_port();
    return () if ($port == Socialtext::HTTP::Ports->STANDARD_HTTPS_PORT());
    return (port => $port);
}

1;

__END__

=head1 NAME

Socialtext::Hostname - URI-making functions for socialtext

=head1 SYNOPSIS

  use Socialtext::URI;

  my $uri = Socialtext::URI::uri(
      path  => '/path/to/thing',
      query => { foo => 1 },
  );

=head1 DESCRIPTION

This module provides a simple wrapper around C<URI::FromHash> to
provide the correct scheme, host, and port for URIs, based on the
Socialtext application config.

=head1 FUNCTIONS

This module wraps the C<uri()> and C<uri_object()> functions from the
C<URI::FromHash> module, and provides the same API as that module.

However, it supplies default "scheme", "host", and "port" parameters
for you based on the Socialtext application conifg and your
environment.

You can, however, override any of these parameters when calling a
function.

=head2 scheme

For now, this is always "http". This is included to allow for the
possibility of a configuraiton to force all request to "https" in the
future.

=head2 host

This will be C<< Socialtext::AppConfig->web_hostname() >>.

=head2 port

If the C<NLW_FRONTEND_PORT> variable is set, it will be
used. Otherwise no "port" is provided.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
