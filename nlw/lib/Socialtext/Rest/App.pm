package Socialtext::Rest::App;
# @COPYRIGHT@

use strict;
use warnings;

use base 'Socialtext::Rest';

use Socialtext::Challenger;
use Socialtext::HTTP ':codes';
use Socialtext::l10n 'loc_lang';

# XXX right?
sub not_authorized {
    my $self = shift;
    return Socialtext::Challenger->Challenge(
        hub      => $self->hub,
        request  => $self->rest->query,
        redirect => $self->rest->query->url( -base => 1 )
    );
}

# duped from Socialtext::Handler::App
sub handler {
    my ($self, $rest) = @_;

    my ($nlw, $html);

    eval {
        $nlw = $self->hub->main;

        # put a rest object on the hub so we can use it
        # elsewhere when doing Socialtext::CGI operations
        $self->hub->rest($rest);

        $self->hub->app($self);

        # Set the locale for this request
        loc_lang( $self->hub->best_locale );

        # html is either a string or IO::Handle
        $html = $nlw->process;
    };

    # XXX this may not interact with auth handling appropriately (i think)
    if ( my $e = $@ ) {
        if (Exception::Class->caught('Socialtext::WebApp::Exception::Redirect')) {
            my $location = $e->message;
            $rest->header(
                -status => HTTP_302_Found,
                -Location => $location,
            );
            return '';
        }
        # REVIEW: What uses this?
        if (Exception::Class->caught('Socialtext::WebApp::Exception::Forbidden')) {
            $self->not_authorized();
        }
        if (Exception::Class->caught('Socialtext::WebApp::Exception::AuthRenewal')) {
            return $self->renew_authentication();
        }
        # XXX Socialtext::Rest does not throw an exception when
        # Params Validate notices the current_workspace parameter
        # is not set because the URI does not have a valid workspace
        # in it.
        if (Exception::Class->caught('Socialtext::WebApp::Exception::NotFound') or $e =~ /current_workspace/ ) {
            # XXX authenticated users get redirected to the workspace list,
            # while everyone else just goes to "/" (which may redirect
            # elsewhere as needed).
            my $redirect_to = $rest->user->is_authenticated ? '/?action=workspace_list' : '/';
            $rest->header(
                -status   => HTTP_302_Found,
                -Location => $redirect_to,
            );
            return ''; # XXX real content here!
        }
        unless (Exception::Class->caught('MasonX::WebApp::Exception::Abort')) {
            return $self->_handle_error($e);
        }
    }

    # headers are set via Socialtext::Headers
    # we need to call print on them to get them
    # set into the rest->header object
    $self->hub->headers->print();

    # does content need to be encoded or decoded?
    return $html;
}


# XXX do good logging and reporting please
sub _handle_error {
    my $self = shift;
    my $error = shift;

    $error = "pid: $$ -> " . $error;

    # what's the REST::App way of error log?
    warn $error, "\n";

    $error = $self->hub->html_escape($error);
    $self->rest->header(
        -type => 'text/html',
        -status => HTTP_500_Internal_Server_Error,
    );
    return "<h1>Software Error:</h1><pre>\n$error</pre>\n";
}

1;
