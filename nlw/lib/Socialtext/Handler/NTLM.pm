package Socialtext::Handler::NTLM;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Handler::Redirect);
use Apache::Constants qw(FORBIDDEN);
use Socialtext::Log qw(st_log);
use Socialtext::Apache::User;

sub real_handler {
    my ($class, $req, $user) = @_;

    # If we've been handed a Guest User, we've got a problem... User was able
    # to authenticate via NTLM, *BUT* they're not a known User in any of our
    # User Factories.
    if ($user->is_guest) {
        st_log->error(
            "have an NTLM authenticated user, but was unable to find him in any of our User Factories"
        );
        return FORBIDDEN;
    }

    # Set a session cookie into the User's browser; we know they're
    # Authenticatd.
    st_log->debug( "setting login session cookie" );
    Socialtext::Apache::User::set_login_cookie($req, $user->user_id);

    # Redirect the User off to where they wanted to be in the first place
    st_log->debug( "let base class redirect User" );
    $class->SUPER::real_handler($req, $user);
}

1;

=head1 NAME

Socialtext::Handler::NTLM - Mod_perl handler to set login cookie for NTLM SSO

=head1 SYNOPSIS

  # in your Apache/Mod_perl config
  <Location /somewhere/requiring/ntlm/authentication>
    SetHandler  perl-script
    PerlHandler +Socialtext::Handler::NTLM
  </Location>

=head1 DESCRIPTION

C<Socialtext::Handler::NTLM> implements the other half of our NTLM SSO
implementation, derived from C<Socialtext::Handler::Redirect>.

Once we have been able to determine that the User can Authenticate using NTLM
(which we let Apache do for us), we set a session cookie in their browser (so
we're not I<constantly> having to do NTLM Authentication requests) and then
redirect them back to the page that they had originally intended to go to.

Please refer to L<Socialtext::Handler::Redirect> for more information on how
redirects are handled.

=head1 METHODS

=over

=item B<real_handler($req, $user)>

The "real" handler method, called by C<Socialtext::Handler>.

Sets the session cookie into the browser, and then calls off to the base class
to do the redirect.

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Socialtext::Handler::Redirect>,
L<Socialtext::Handler>,
L<Socialtext::Apache::Authen::NTLM>,
L<Socialtext::Challenger::NTLM>.

=cut
