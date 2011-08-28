package Socialtext::Challenger::NoLogin;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::WebApp;

use base 'Socialtext::Challenger::Base';

sub challenge {
    my $class = shift;
    my %p = @_;

    my $request  = delete $p{request};
    my $redirect = delete $p{redirect};

    my $app = Socialtext::WebApp->NewForNLW;
    $request  ||= $app->apache_req;
    $redirect ||= $request->parsed_uri->unparse;

    my $to = $class->is_mobile($redirect) ? '/m/nologin' : '/nlw/nologin.html';
    $app->redirect($to);
}

1;

=head1 NAME

Socialtext::Challenger::NoLogin - Custom challenger with *NO* login form

=head1 SYNOPSIS

  Do not instantiate this class directly.
  Use Socialtext::Challenger instead.

=head1 DESCRIPTION

When configured for use, this Challenger presents to unauthenticated Users a
page that contains B<NO> login form.

Useful when credentials are to be provided by some means I<other than> username and password (e.g. SSL Certificate).

=head1 METHODS

=over

=item B<Socialtext::Challenger::NoLogin-E<gt>challenge(%p)>

Custom challenger.

Not to be called directly.  Use C<Socialtext::Challenger> instead.

=back

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Socialtext, Inc., All Rights Reserved.

=head1 SEE ALSO

L<Socialtext::Challenger>.

=cut
