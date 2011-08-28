# @COPYRIGHT@
package Socialtext::Handler;
use strict;
use warnings;

use Apache::Constants qw(:response :common);
use Apache::SubProcess;
use Apache::URI;

use File::Find ();
use Socialtext::Apache::User;

use Socialtext;
use Socialtext::Hub; # preload all other classes
use Socialtext::AppConfig;
use Socialtext::CredentialsExtractor::Client::Sync;
use Socialtext::RequestContext;
use Socialtext::WebApp;
use Socialtext::TT2::Renderer;
use Socialtext::User;
use Socialtext::Challenger;
use Socialtext::l10n qw/loc_lang/;

# provides a way to skip this when running tests
_preload_templates()
    unless $ENV{NLW_HANDLER_NO_PRELOADS} || not $ENV{MOD_PERL};

sub allows_guest {1}

sub challenge {
    my $class = shift;
    return Socialtext::Challenger->Challenge(@_);
}

sub handler ($$) {
    my $class = shift;

    # set max upload size
    my $apr = Apache::Request->instance( shift, POST_MAX => ( 1024 ** 2 ) * 50 );

    my $user = $class->authenticate($apr) || $class->guest($apr);

    return $class->challenge(request => $apr) unless $user;

    return $class->real_handler($apr, $user);
}

sub authenticate {
    my $class   = shift;
    my $request = shift;

    my $client = Socialtext::CredentialsExtractor::Client::Sync->new();
    my %env    = (
        $request->cgi_env,
        AUTHORIZATION => $request->header_in('Authorization'),
    );
    my $creds  = $client->extract_credentials(\%env);
    return unless ($creds->{valid});

    my $user = Socialtext::User->new(user_id => $creds->{user_id});
    return if (!$user or $user->is_deleted or $user->is_guest);

    $request->connection->user($user->username);
    return $user;
}

sub guest {
    my ($class, $r) = @_;
    return $class->allows_guest($r) ? Socialtext::User->Guest : undef;
}

sub _preload_templates {
    my @files = Socialtext::TT2::Renderer->PreloadTemplates();

    my $server = Apache->server;
    my $uid = $server->uid;
    my $gid = $server->gid;

    my $chown =
        sub { chown $uid, $gid, $File::Find::name
                  or die "Cannot chown $File::Find::name to $uid.$gid: $!" };

    File::Find::find(
        {
            wanted   => $chown,
            no_chdir => 1,
        },
        Socialtext::AppConfig->template_compile_dir
    );
}

sub handle_error {
    my $class = shift;
    my $r     = shift;
    my $error = shift;
    my $nlw   = shift;

    if (ref($error) ne 'ARRAY') {
        $error = "pid: $$ -> " . $error;
        $r->log_error($error);
        $error = $nlw->html_escape($error) if $nlw;
        $error = [ $error ];
    }

    my %vars = (
        debug => Socialtext::AppConfig->debug,
        errors => $error,
    );

    return $class->render_template($r, 'errors/500.html', \%vars);
}

sub render_template {
    my $class    = shift;
    my $r        = shift;
    my $template = shift;
    my $vars     = shift || {};
    my $paths    = $vars->{paths} || [];

    my $renderer = Socialtext::TT2::Renderer->instance;
    eval {
        $r->content_type("text/html");
        $r->send_http_header;
        $r->print(
                  $renderer->render(
                                    template => $template,
                                    vars     => $vars,
                                    paths    => $paths,
                                   )
                 );
    };
    if ($@) {
        if ($@ =~ /\.html: not found/) {
            return NOT_FOUND;
        }
        warn $@ if $@;
    }
    return OK;
}

sub r { shift->{r} }

sub session {
    my $self = shift;
    $self->{session} ||=  Socialtext::Session->new( $self->r );
    return $self->{session};
}

sub redirect {
    my $self = shift;
    my $redirect_to = shift;

    # Make sure that the URI is *relative* (no absolute URIs allowed)
    my $uri = URI->new($redirect_to);
    if ($uri->scheme) {
        # Given an absolute URI.  If it points to somewhere _other_than_ this
        # machine, fail.
        my $host      = $uri->host();
        my $this_host = Socialtext::AppConfig->web_hostname();
        if ($host ne $this_host) {
            require Socialtext::Log;
            Socialtext::Log::st_log->error(
                "redirect attempted to external source; $redirect_to");
            return FORBIDDEN;
        }
    }

    # force the URI to be relative (preserving embedded query string), and
    # redirect to it
    my $relative_uri = $uri->path_query();

    $self->r->header_out(Location => $relative_uri);
    return REDIRECT;
}


1;

__END__

=head1 NAME

Socialtext::Handler - A base class for NLW mod_perl handlers

=head1 SYNOPSIS

  use base 'Socialtext::Handler';


  sub workspace_uri_regex => qr{/path/to/workspace/([^/]+)};

  sub foo {
      my $nlw = $class->get_nlw($r);
  }

=head1 DESCRIPTION

This module hooks NLW up to mod_perl.

=head1 ADDITIONAL

We should really use something like C<Class::Autouse>, which loads
things on demand outside mod_perl and at startup under mod_perl.

=cut
