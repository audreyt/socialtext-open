# @COPYRIGHT@
package Socialtext::Rest::Help;
use strict;
use warnings;
use base 'Socialtext::Rest';

use Socialtext::HTTP ':codes';
use Socialtext::Log 'st_log';
use Socialtext::Workspace;

sub handler {
    my ( $self, $rest ) = @_;

    # Redirect to the right help workspace, or do a 404.
    my $ws = Socialtext::Workspace->help_workspace();
    if ($ws) {
        my $uri = get_uri( $rest, $ws->name );
        $rest->header(
            -status => HTTP_302_Found,
            -Location => $uri,
        );
        return ''
    }
    else {
        return $self->no_workspace("help");
    }
}

# Redirect the request, but rewrite /help to /$ws where $ws is the real help
# workspace.
sub get_uri {
    my ( $rest, $ws_name ) = @_;
    my $uri = $rest->query->url( -path_info => 1, -query => 1 ) || "";
    $uri =~ s{/help/}{/$ws_name/};
    return $uri;
}

1;
