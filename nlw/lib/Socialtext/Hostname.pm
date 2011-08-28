# @COPYRIGHT@
package Socialtext::Hostname;

use strict;
use warnings;

use Sys::Hostname ();

our $VERSION = '0.01';

# REVIEW - this all works fine with 3-part fully-qualified domain
# names (foo.socialtext.com), but I'm not if it's similarly correct
# for 4+ part names. Review by someone with more expertise in this
# sort of stuff would be good.

sub hostname {
    my $local = $ENV{HOSTNAME} || Sys::Hostname::hostname();

    return (split /\./, $local)[0];
}

sub fqdn {
    my $local = $ENV{HOSTNAME} || Sys::Hostname::hostname();

    return $local unless _is_short($local);

    return (gethostbyname($local))[0];
}

sub _is_short {
    return 0 if $_[0] =~ /\./;
    return 1;
}

sub domain {
    my $fqdn = fqdn();

    $fqdn =~ s/.+\.(\w+\.\w+)$/$1/;

    return $fqdn;
}


1;

__END__

=head1 NAME

Socialtext::Hostname - Provides the local machine's host and domain names

=head1 SYNOPSIS

Perhaps a little code snippet.

  use Socialtext::Hostname;

  my $fqdn = Socialtext::Hostname::fqdn();
  my $host = Socialtext::Hostname::hostname();
  my $domain = Socialtext::Hostname::domain();

=head1 DESCRIPTION

This module provides a few functions for determining the local
machine's host and domain names.

=head1 FUNCTIONS

This module provides the following functions:

=head2 hostname()

Always returns the short version of the machine's hostname (without a
domain name).

=head2 fqdn()

Returns the machine's fully-qualified domain name (hostname plus
domain name).

=head2 domain()

Returns just the machine's domain name.

=head1 SEE ALSO

Sys::Hostname - this basically returns whatever is in
F</etc/hostname>, which could be fully-qualified or not.

Sys::Hostname::FQDN - It's a lot of code to do very little, and
pointlessly includes an XS reimplementation of Sys::Hostname.

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005-2006 Socialtext, Inc., All Rights Reserved.

=cut
