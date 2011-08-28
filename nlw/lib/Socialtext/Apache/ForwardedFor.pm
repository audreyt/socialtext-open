package Socialtext::Apache::ForwardedFor;
# @COPYRIGHT@

use strict;
use warnings;
use Apache::Constants qw(OK DECLINED);
use List::MoreUtils qw(uniq);
use Regexp::Common qw(net);

sub handler {
    my $r = shift;

    # only trust "X-Forwarded-For" header if the request comes in from our own
    # Apache front-end.
    return DECLINED unless ($r->connection->remote_ip eq '127.0.0.1');

    # get the list of candidate IPs, from the "X-Forwarded-For" header and the
    # current "remote_ip"
    my @ips = split(/\s*,\s*/, $r->header_in('X-Forwarded-For') || '');
    push @ips, $r->connection->remote_ip;

    # trim the list to a unique list of valid IPs
    @ips = uniq grep { /^$RE{net}{IPv4}$/ } @ips;

    # set the connection remote_ip to the IP address that's closest to the
    # end-user.
    $r->connection->remote_ip($ips[0]);
    return OK;
}

1;

=head1 NAME

Socialtext::Apache::ForwardedFor - Extract IP address from "X-Forwarded-For" header

=head1 SYNOPSIS

In your Apache configuration:

  PerlPostReadRequestHandler +Socialtext::Apache::ForwardedFor

=head1 DESCRIPTION

C<Socialtext::Apache::ForwardedFor> resets the IP address of the HTTP
connection to that of the end-client, based on the information provided in the
C<X-Forwarded-For> header.

A Socialtext Appliance is configured with a light-weight Apache front-end to
serve up static requests, with a heavy-weight Apache back-end that handles all
of the dynamic content generation.  This is the recommended practice as
outlined in the Mod_Perl Guide.

A problem when running in this configuration is that the "remote_ip" for the
Mod_Perl back-end is that of the Apache front-end; 127.0.0.1.  Works, but
doesn't provide any sort of accurate representation of what the B<end user's>
IP address is, making it difficult to track usage through the back-end logs.

C<Socialtext::Apache::ForwardedFor> fixes this up by grabbing the list of IP
addresses out of the C<X-Forwarded-For> header and setting the "remote_ip" to
the IP address that as close to the original end-user as is possible.

If the connection had already been proxied before it hit our Apache front-end
it I<is> possible that the information in the C<X-Forwarded-For> header is
either inaccurate or invalid.  For this reason we explicitly state here that
we try to get you B<as close to the original end-user as is possible.>  Isn't
a guarantee, its a best effort.

=head1 METHODS

=over

=item handler

Mod_perl PostReadRequest handler method, which extracts IP information from
the "X-Forwarded-For" header and makes that look like the remote connection
IP.

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
