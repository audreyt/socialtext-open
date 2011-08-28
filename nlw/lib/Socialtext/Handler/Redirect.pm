package Socialtext::Handler::Redirect;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Handler);
use Apache::Constants qw(FORBIDDEN);
use Socialtext::Log qw(st_log);
use Socialtext::AppConfig;

sub real_handler {
    my ($class, $req, $user) = @_;

    # XXX: create a new Handler *object*; ST::Handler tries to be *BOTH* a
    # Mod_perl handler _and_ an object.  Really should be cleaned up, but this
    # one line makes it possible to do "$self->redirect(...)" later and have
    # it work. :(
    my $self = bless { r => $req }, __PACKAGE__; # new can kiss my ass

    # Get the URI that we're supposed to be redirect the User off to
    my $redirect_to = $req->param('redirect_to') || '/';

    st_log->debug("redirect: $redirect_to");
    return $self->redirect($redirect_to);
}

1;

=head1 NAME

Socialtext::Handler::Redirect - Mod_perl handler to redirect to a URI

=head1 SYNOPSIS

  # in your Apache/Mod_perl config
  <Location /somewhere/over/here>
    SetHandler  perl-script
    PerlHandler +Socialtext::Handler::Redirect
  </Location>

=head1 DESCRIPTION

C<Socialtext::Handler::Redirect> implements a really simple HTTP redirection
handler, derived from C<Socialtext::Handler>.

This handler simply redirects the browser off to whatever URI has been given
in the C<redirect_to> form parameter.

If no C<redirect_to> parameter has been provided, "/" is used as a default.

If the C<redirect_to> parameter is an I<absolute URI> (e.g. "http://..."),
then it B<must> point to B<this> host (as listed in
F</etc/socialtext/socialtext.conf> under C<web_hostname>).  Attempts to
redirect to an external source are B<not> allowed and will return a "403
Forbidden" response.

=head1 METHODS

=over

=item B<real_handler($req, $user)>

The "real" handler method, called by C<Socialtext::Handler>.  Performs the
redirect.

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Handler>.

=cut
