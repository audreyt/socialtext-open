package Socialtext::PlackApp;
use 5.12.0;
use parent 'Exporter';
our @EXPORT = 'PerlHandler';

use signatures;
use CGI::PSGI;
use URI;
use Log::Dispatch;
use Module::Load;
use Encode ();
use Apache::Constants qw(:response);
use Socialtext::HTTP::Ports;
use Socialtext::AppConfig;

our ($Request, $Response, $CGI);

sub PerlHandler ($handler, $access_handler) {
    load($handler);

    state $https_port = Socialtext::HTTP::Ports->https_port;
    my $is_dev_env = Socialtext::AppConfig->is_dev_env;

    return sub ($env) {
        delete $env->{"psgix.io"};

        my $is_https_request = ($env->{HTTP_X_FORWARDED_PORT} == $https_port);
        $env->{HTTPS} = 'on' if $is_https_request;

        local $Request = Socialtext::PlackApp::Request->new($env);
        local $Response = Socialtext::PlackApp::Response->new(200);
        local $CGI = CGI::PSGI->new($env);

        my $app = $handler->can('new') ? $handler->new(
            request => $Request,
            query => $CGI,
        ) : $handler;

        local %ENV = (
            %ENV,
            REST_APP_RETURN_ONLY => 1,
            NLWHTTPSRedirect => $is_https_request,
        );
        map { $ENV{$_} = $env->{$_} }
            grep { /^(?:HTTP|QUERY|REQUEST|REMOTE|SCRIPT|PATH|CONTENT|SERVER)_/ }
            keys %{$env};

        $ENV{NLW_DEV_MODE} = $env->{NLW_DEV_MODE} = $is_dev_env;
        $ENV{NLW_MOBILE_BROWSER} = $env->{NLW_MOBILE_BROWSER} = (
            $env->{HTTP_USER_AGENT} =~ m{
                ^BlackBerry |
                ^Nokia |
                Palm |
                SymbianOS |
                Windows\s+CE |
                ^hiptop |
                iPhone |
                Android
            }x
        );

        if ($access_handler) {
            load $access_handler;
            my $rv = $access_handler->can('handler')->($Request);
            if ($rv != OK) {
                $Response->status($rv);
                return $Response->finalize;
            }
        }

        my ($h, $out) = $app->handler($Request);

        # Copied from Socialtext::CleanupHandler:
        use Socialtext::Cache ();
        use Socialtext::SQL ();
        Socialtext::Cache->clear();
        File::Temp::cleanup();
        Socialtext::SQL::invalidate_dbh();
        @Socialtext::Rest::EventsBase::ADD_HEADERS = ();

        if (!defined $out) {
            # A simple status is returned
            $Response->status($h || 200);
            return $Response->finalize;
        }

        my @headers = $h->header;
        $Response->content_type('text/html; charset=UTF-8');

        my $status;

        while (my $key = lc(shift @headers)) {
            my $val = shift @headers;
            $key =~ s/^-//;
            given ($key) {
                when ('status') {
                    $status = int($val) || $status;
                    next;
                }
                when ('type') {
                    $Response->content_type($val);
                    next;
                }
                when ('location') {
                    $status ||= 302; # Fall through
                }
            }
            $Response->headers->push_header($key => $val);
        }

        $Response->status($status || 200);

        Encode::_utf8_off($out);
        $Response->body($out);
        return $Response->finalize;
    }
};

### Apache method overrides ###
sub Apache::Cookie::new { shift; shift; Socialtext::PlackApp::Cookie->new(@_) }
sub Apache::Cookie::fetch { shift; @_ ? $Request->cookies->{$_[0]} : $Request->cookies }
sub Apache::request { $Request }
sub Apache::Request::new { $Request }
sub Apache::Request::instance { $Request }

BEGIN {
    $INC{$_} = __FILE__ for qw(
        Apache/Cookie.pm
        Apache/Request.pm
        Apache/SubProcess.pm
        Apache/URI.pm
        Apache.pm
    );
    *URI::unparse = *URI::as_string;
}

package Socialtext::PlackApp::Cookie;
use parent 'CGI::Cookie';
use methods-invoker;

*Response = *Socialtext::PlackApp::Response;
method new (%opts) {
    delete $opts{'-expires'} unless $opts{'-expires'};
    $->SUPER::new(%opts);
}
method bake {
    $Response->err_headers_out->add('Set-Cookie', $->as_string);
}

package Socialtext::PlackApp::Connection;
use parent 'Class::Accessor';
__PACKAGE__->mk_accessors(qw(user));

package Socialtext::PlackApp::Response;
use parent 'Plack::Response';
use methods-invoker;
method err_headers_out { $self }
method headers_out { $self }
method add ($key, $val) {
    if (lc $key eq 'set-cookie') {
        $val .= '; HttpOnly';
    }
    $->headers->push_header(lc $key, $val);
}
method set ($key, $val) {
    $->headers->remove_header(lc $key);
    $->add($key, $val);
}

package Socialtext::PlackApp::Request;
use parent 'Plack::Request';
use methods-invoker;
use Encode ();
use URI::Escape;
no warnings 'redefine';

*Response = *Socialtext::PlackApp::Response;

method content_type {
    if (@_) {
        return $Response->content_type(@_);
    }
    $->SUPER::content_type();
}

method uri {
    if (caller =~ /^Socialtext::/) {
        my $path = $->SUPER::uri->path;
        return Encode::decode_utf8(Encode::encode(latin1 => $path));
    }
    $->SUPER::uri();
}

method print {
    Encode::_utf8_off($_) for @_;
    $Response->body(@_);
}

method header_out {
    Encode::_utf8_off($_) for @_;
    $Response->header(@_);
}

method send_http_header { undef }
method prev { undef }
method header_in ($key) { scalar $->header($key) }
method args { wantarray ? %{ $->parameters } : $ENV{QUERY_STRING} }
method content { wantarray ? () : $->SUPER::content }
method cgi_env { %ENV }
method parsed_uri { URI->new($ENV{REQUEST_URI}) }
method log_error { warn @_ }
method connection { $self->{_connection} //= Socialtext::PlackApp::Connection->new }
method subprocess_env ($key, $val) {
    if ($key eq 'nokeepalive') {
        $->env->{'socialtext.keep-alive.force'} = !$val;
    }
}
method headers_out { $Response->headers_out(@_) }
method err_headers_out { $Response->err_headers_out(@_) }

__END__

=head1 NAME

Socialtext::PlackApp - Plack adapter to Socialtext Handlers

=head1 SYNOPSIS

    use Plack::Builder;
    use Socialtext::PlackApp;
    builder {
        mount '/nlw/control' => PerlHandler('Socialtext::Handler::ControlPanel'),
        mount '/nlw' => PerlHandler('Socialtext::Handler::Authen'),
        mount '/' => PerlHandler('Socialtext::Handler::REST'),
    }

=head1 DESCRIPTION

This module exports a single function, C<PerlHandler>, that takes a
L<Socialtext::Handler> subclass and returns a Plack application for it.

=cut
