# @COPYRIGHT@
package Socialtext::Rest::Challenge;
use strict;
use warnings;

use base 'Socialtext::Rest';
use Socialtext::Challenger;
use Socialtext::HTTP ':codes';
use Socialtext::Log qw(st_log);
use URI::Escape qw(uri_unescape);

sub handler {
    my ( $self, $rest ) = @_;

    # If the query string contains a "redirect_to" parameter, use that as the
    # URL to redirect the User to.  Otherwise, treat the *entire* URL as the
    # redirect.
    #
    # This allows for Challengers to set themselves up to be called once on an
    # initial request for:
    #
    #       /challenge?<url>
    #
    # and to then build a URL to let them get called a second time with actual
    # query params by redirecting back to:
    #
    #       /challenge?redirect_to=<url>&key=val&key=val...
    my $uri;
    if ($rest->query->param('redirect_to')) {
        $uri = $rest->query->param('redirect_to');
    }
    else {
        $uri = $rest->query->query_string();
        $uri =~ s/^keywords=//;
    }
    eval {
        Socialtext::Challenger->Challenge( redirect => uri_unescape($uri) );
    };

    if ( my $e = $@ ) {
        if ( Exception::Class->caught('Socialtext::WebApp::Exception::Redirect') )
        {
            my $location = $e->message;
            $rest->header(
                -status   => HTTP_302_Found,
                -Location => $location,
            );
            return '';
        }
        st_log->info("Challenger Error: $e");
    }
    $self->rest->header(
        -status => HTTP_500_Internal_Server_Error,
    );
    return 'Challenger Did not Redirect';
}

1;

=head1 NAME

Socialtext::Rest::Challenge - Provides a handler() sub for challenges

=cut
