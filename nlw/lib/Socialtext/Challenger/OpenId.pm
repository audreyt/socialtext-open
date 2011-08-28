package Socialtext::Challenger::OpenId;
# @COPYRIGHT@

use strict;
use warnings;


use Net::OpenID::Consumer;
use Apache;
use Apache::Request;
use Socialtext::User;
use Socialtext::Apache::User;
use LWP::UserAgent;
use Socialtext::WebApp;
use URI::Escape qw (uri_unescape);

=head1 NAME

Socialtext::Challenger::OpenId - Challenge with the default login screen

=head1 SYNOPSIS

    Do not instantiate this class directly. Use L<Socialtext::Challenger>

=head1 DESCRIPTION

When configured for use, this Challenger will redirect a request
to the OpenId login system.

=head1 METHODS

=over

=item B<Socialtext::Challenger::OpenID-E<gt>challenge(%p)>

Custom challenger.

Not to be called directly.  Use C<Socialtext::Challenger> instead.

=back

=cut

sub challenge {
    my $class    = shift;
    my %p        = @_;
    my $hub      = $p{hub};
    my $request  = $p{request};
    my $redirect = $p{redirect};
    my $type;

    # REVIEW: be nice to change how this is done in the future
    my $app = Socialtext::WebApp->NewForNLW;
    $request = Apache::Request->instance( Apache->request );

    my $claimed_identity =
          $request->param('openid.identity')
        ? $request->param('openid.identity')
        : $request->param('identity');

    if ( !$claimed_identity ) {
        return undef;
    }

    $claimed_identity = uri_unescape($claimed_identity);
    if ( $claimed_identity =~ /^http/ ) {
        $claimed_identity =~ s#^http(s)?://##g;
        $claimed_identity =~ s#/$##g;
    }
    $claimed_identity =~ s/\s//g;

    my $csr = Net::OpenID::Consumer->new(
        ua              => LWP::UserAgent->new,
        args            => $request,
        consumer_secret => 'THIS IS MY SECRET!',
    );

    # if we've NOT returned from the openid server with some info
    # do a redirect to the open id server
    if ( !$request->param('openid.mode') ) {
        my $uri = _get_uri($request);
        my ($full_uri, $base_uri);

        $full_uri = $uri->unparse;

        # get rid of the extra bits on the url to have
        # just base
        $uri->query(undef);
        $uri->path(undef);
        $base_uri = $uri->unparse;

        $claimed_identity = $csr->claimed_identity($claimed_identity);

        if ( !$claimed_identity && !$request->param('openid.identity') ) {
            warn "Socialtext::Challenger::OpenId RETURNING UNDEF\n";
            return undef;
        }
        my $check_url = $claimed_identity->check_url(
            return_to  => "$full_uri",
            trust_root => "$base_uri"
        );
        $app->redirect( $check_url );
    }
    else {
        if ( my $setup_url = $csr->user_setup_url ) {
            $app->redirect( $setup_url);
        }
        elsif ( $csr->user_cancel ) {
            $app->redirect( $ENV{HTTP_REFERER} );
        }
        elsif ( my $vident = $csr->verified_identity ) {
            my $verified_url = $vident->url;
            if ( !_set_cookie($claimed_identity) ) {
                return undef;
            }
        }
        $app->redirect ( "/" );
    }
}

sub _get_uri {
    my $request = shift;
    my $uri     = $request->parsed_uri;
    $uri->hostname( $request->hostname );

    my $xfh = $request->header_in('X-Forwarded-Host');
    if ( $xfh && ( $xfh =~ /:(\d+)$/ ) ) {
        my $front_end_port = $1;
        if (   $front_end_port
            && ( $front_end_port != 80 )
            && ( $front_end_port != 443 ) ) {
            $uri->port($front_end_port);
        }
    }
    $uri->scheme( $ENV{'NLWHTTPSRedirect'} ? 'https' : 'http' );

    return $uri;
}

sub _set_cookie {
    my $identity = shift;
    my $user = Socialtext::User->new( username => $identity );
    return unless $user;
    return Socialtext::Apache::User->set_login_cookie(
        Apache->request,
        $user->user_id,
        '+12M',
    );
}

1;

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2007 Socialtext, Inc., All Rights Reserved.

=cut
