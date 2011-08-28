package Socialtext::Rest::Feed;
# @COPYRIGHT@
use strict;
use warnings;

use Socialtext::Authz;
use Socialtext::HTTP ':codes';
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::Timer;

use base 'Socialtext::Rest';

sub GET {
    my ($self, $rest) = @_;

    Socialtext::Timer->Continue('GET_feed');
    if (! $self->workspace) {
        $rest->header(
            -status => HTTP_404_Not_Found,
        );
        Socialtext::Timer->Pause('GET_feed');
        return 'Invalid Workspace';
    }

    my $authz = Socialtext::Authz->new;
    unless (
        $self->workspace->permissions->is_public or
        $authz->user_has_permission_for_workspace(
            user       => $self->rest->user,
            permission => ST_READ_PERM,
            workspace  => $self->workspace,
        )
        ) {

        $rest->header(
            -status             => HTTP_401_Unauthorized,
            '-WWW-Authenticate' => 'Basic realm="Socialtext"'
        );
        Socialtext::Timer->Pause('GET_feed');
        return 'Invalid Workspace';
    }

    # put a rest object on the hub so we can use it
    # elsewhere when doing Socialtext::CGI operations
    $self->hub->rest($rest);

    # XXX uses default type and category, need to improve that
    # syndicate($type, $category)
    my $feed; 
    my $xml;
    eval { 
        $feed = $self->hub->syndicate->syndicate;
        Socialtext::Timer->Continue('GET_feed_as_xml');
        $xml = $feed->as_xml;
        Socialtext::Timer->Pause('GET_feed_as_xml');
    };

    if (Exception::Class->caught('Socialtext::Exception::NoSuchResource')) {
        $rest->header(
            -status => HTTP_404_Not_Found,
        );
        Socialtext::Timer->Pause('GET_feed');
        return 'Page Not Found';
    }

    if ($@ and not Exception::Class->caught('MasonX::WebApp::Exception::Abort')) {
        warn $@;
        $rest->header(
            -status => HTTP_500_Internal_Server_Error,
        );
        Socialtext::Timer->Pause('GET_feed');
        return $@;
    }

    $rest->header(
        -status => HTTP_200_OK,
        -type => $feed->content_type,
    );
    Socialtext::Timer->Pause('GET_feed');
    return $xml;
}

1;

