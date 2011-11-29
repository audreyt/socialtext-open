package Socialtext::Handler::Default;
# @COPYRIGHT@
use Moose;
use Socialtext;
use Socialtext::BrowserDetect;
use Socialtext::Workspace;
use Socialtext::HTTP qw(:codes);
use URI::Escape qw(uri_escape);
use namespace::clean -except => 'meta';

use constant type => 'default';

extends 'Socialtext::Rest::Entity';

sub handler {
    my ($self, $rest) = @_;

    if (!$rest->user->is_authenticated) {
        my $default_ws = Socialtext::Workspace->Default();
        if ($default_ws) {
            return $self->redirect( '/' . $default_ws->name );
        }
        return $self->redirect_to_login;
    }

    if (my $action = $rest->query->param('action')) {
        my $res;
        eval { 
            $self->hub->rest($rest);
            $res = $self->hub->process 
        };
        if (my $e = $@) {
            my $redirect_class = 'Socialtext::WebApp::Exception::Redirect';
            if (Exception::Class->caught($redirect_class)) {
                 $rest->header(
                     -status => HTTP_302_Found,
                     -Location => $e->message,
                 );
                 return '';
            }
            elsif (Exception::Class->caught('Socialtext::WebApp::Exception::AuthRenewal')) {
                return $self->renew_authentication;
            }
        }
        $rest->header(-type => 'text/html; charset=UTF-8', # default
                      $self->hub->rest->header);
        return $res;
    }
    else {
        my $redirect_to;

        my $default_ws = Socialtext::Workspace->Default();
        if ($default_ws) {
            $redirect_to = '/' . $default_ws->name;
        }
        elsif ($self->hub->helpers->signals_only) {
            $redirect_to = '/st/signals';
        }
        elsif ($rest->user->can_use_plugin('dashboard')) {
            $redirect_to = '/st/dashboard';
        }
        else {
            my $is_mobile  = Socialtext::BrowserDetect::is_mobile();
            $redirect_to = $is_mobile
                ? '/m/workspace_list'
                : 'action=workspaces_listall';
        }
        return $self->redirect( $redirect_to );
    }
}

sub redirect_to_login {
    my $self = shift;
    my $uri = uri_escape($ENV{REQUEST_URI} || '');
    return $self->redirect("/challenge?$uri");
}

sub redirect {
    my ($self,$target) = @_;
    unless ($target =~ /^(https?:|\/)/i or $target =~ /\?/) {
        $target = $self->hub->cgi->full_uri . '?' . $target;
    }
    $self->rest->header(
        -status => HTTP_302_Found,
        -Location => $target,
    );
    return;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Handler::Default - root handler, redirects to other handlers

=head1 SYNOPSIS

  Used by the URI map to handle /

=head1 DESCRIPTION

Handles /, redirects to appropriate places for each user.

=cut
