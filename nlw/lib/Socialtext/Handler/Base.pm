package Socialtext::Handler::Base;
# @COPYRIGHT@

use Moose::Role;
use Socialtext::HTTP ':codes';
use Socialtext::HTTP::Cookie;
use Socialtext::Gadgets::Util qw(share_path plugin_dir);
use Socialtext::Session;
use Socialtext::l10n qw/loc_lang loc/;
use Socialtext::JSON qw(encode_json decode_json);
use Socialtext::AppConfig;
use namespace::clean -except => 'meta';

requires 'get_html';
requires 'if_authorized_to_edit';
requires 'if_authorized_to_view';

has 'session' => (
    is => 'ro', isa => 'Socialtext::Session',
    lazy_build => 1,
);
sub _build_session {
    return Socialtext::Session->new;
}

has 'uri' => (
    is => 'ro', isa => 'Str',
    lazy_build => 1,
);

sub _build_uri {
    my ($uri) = $ENV{REQUEST_URI} =~ m{^([^?]+)};
    return $uri;
}

sub template_vars {
    my $self = shift;
    my %global_vars = $self->hub->helpers->global_template_vars;
    return {
        params => { $self->rest->query->Vars },
        share => share_path,
        workspaces => [$self->hub->current_user->workspaces->all],
        as_json => sub {
            my $json = encode_json(@_);

            # hack so that json can be included in other <script> 
            # sections without breaking stuff
            $json =~ s!</script>!</scr" + "ipt>!g;

            return $json;
        },
        %global_vars,
    };
}

sub render_template {
    my ($self, $template, $vars) = @_;
    my $renderer = Socialtext::TT2::Renderer->instance;
    return $renderer->render(
        template => $template,
        paths => $self->template_paths,
        vars => {
            %{$self->template_vars},
            %$vars,
        },
    );
}

sub GET {
    my ($self, $rest) = @_;

    my $res;

    eval {
        loc_lang( $self->hub->best_locale );
        $res = $self->if_authorized_to_view(sub {
            $self->rest->header('Content-Type' => 'text/html; charset=utf-8');
            return $self->get_html;
        });
    };
    if ($@) {
        warn $@;
        return $self->error(loc("error.display-page", Socialtext::AppConfig->support_address));
    }

    return $res;
}

has 'template_paths' => (
    is => 'ro', isa => 'ArrayRef',
    lazy_build => 1,
);
sub _build_template_paths {
    my $self = shift;
    return [
        @{Socialtext::Gadgets::Util::template_paths()},
        @{$self->hub->skin->template_paths},
    ];
}

sub error {
    my ($self, $error) = @_;
    return $self->render_template('view/error', { error_string => $error });
}

sub unless_authen_needs_renewal {
    my ($self, $cb) = @_;
    return $self->renew_authentication if Socialtext::HTTP::Cookie->NeedsRenewal;
    return $cb->();
}

sub not_authenticated {
    my $self = shift;
    my $redirect_to = $self->rest->request->parsed_uri->unparse;
    $self->redirect("/challenge?$redirect_to");
    return '';
}

sub renew_authentication {
    my $self = shift;
    $self->session->add_error(
        loc("error.relogin")
    );
    my $redirect_to = $self->rest->request->parsed_uri->unparse;
    $self->redirect("/challenge?$redirect_to");
    return '';
}

sub invalid {
    my $self = shift;
    my $msg  = shift || loc('error.bad-request');
    $self->rest->header(-status => HTTP_400_Bad_Request);
    return $self->error($msg);
}

sub not_found {
    my $self = shift;
    my $msg = shift || loc("error.no-such-page", Socialtext::AppConfig->support_address);

    $self->rest->header(-status => HTTP_404_Not_Found);
    return $self->error($msg);
}

sub forbidden {
    my $self = shift;
    my $msg = shift || loc("error.page-forbidden", Socialtext::AppConfig->support_address);

    $self->rest->header(-status => HTTP_403_Forbidden);
    return $self->error($msg);
}

sub redirect {
    my ($self, $url) = @_;
    $self->rest->header(
        -status => HTTP_302_Found,
        -Location => $url,
    );
    return '';
}

sub permanent_redirect {
    my ($self, $url) = @_;
    $self->rest->header(
        -status => HTTP_301_Moved_Permanently,
        -Location => $url,
    );
    return '';
}

1;

=head1 NAME

Socialtext::Handler::Base - Baseline Role for handlers

=head1 SYNOPSIS

  package Socialtext::Handler::Base;
  with 'Socialtext::Handler::Base';

=head1 DESCRIPTION

Baseline Role for handlers, containing common functionality that's useful not
only for Containers but for other types of Handlers as well.

=cut
