package Socialtext::Async::HTTPD;
# @COPYRIGHT@

# Hi, Socialtext devs:
#
# Please consider writing a PSGI app instead of using this module.
#
# Sincerely,
#
# ~stash

# Hi, Socialtext devs heeding stash++'s advice above:
#
# Please consider running the said PSGI app in Starman
# (http://search.cpan.org/dist/Starman/), a high-performance
# preforking Plack server, optionally with "starman --preload-app"
# to minimize memory footprint.
#
# Cheers,
# -au

use warnings;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket qw/tcp_server/;
use HTTP::Parser::XS qw/parse_http_request/;
use HTTP::Response ();
use bytes; no bytes; # just load it

use base 'Exporter';
our $VERSION = '1.0';
our @EXPORT = qw(http_server);
our @EXPORT_OK = qw(http_server serialize_response);

sub http_server($$$) {
    my $host = shift;
    my $port = shift;
    my $cb = shift;
    return tcp_server $host, $port, sub { handle_http(@_,$cb) };
}

my $CRLF = "\015\012";
my $EOH = $CRLF.$CRLF;
sub handle_http {
    my $fh = shift;
    my $host = shift;
    my $port = shift;
    my $cb = shift;

    my $handle; $handle = AnyEvent::Handle->new(
        fh => $fh,
        on_error => sub {
            shift;
            my $fatal = shift;
            my $error = shift;
            $cb->($handle, undef, undef, $fatal, $error);
        },
        on_eof => sub {
            shift;
            $cb->($handle, undef, undef, 0, 'EOF');
        },
    );

    $handle->unshift_read(line => $EOH => sub {
        shift;
        my %env;

        my $head = shift;
        $head .= $EOH;
        my $result = eval { parse_http_request($head, \%env) } || -3;
        undef $head; # don't need to keep the raw headers around

        if ($result < 0) {
            # request is broken (fatal)
            my $error = "Malformed HTTP request; ".
                "host:$host port:$port HTTP-Parser-XS-code:$result";
            $cb->($handle, undef, undef, 1, $error);
        }
        elsif ($result == 0) {
            # no more data to read, exec the callback
            $cb->($handle, \%env);
        }
        else {
            # exec the callback after the body arives
            $handle->unshift_read(chunk => $env{CONTENT_LENGTH}, sub {
                $cb->($handle, \%env, \$_[1]);
            });
        }
        return;
    });

    return;
}

sub serialize_response {
    my $resp = shift;
    $resp->header('Content-Length', bytes::length($resp->content));
    return "HTTP/1.0 ".$resp->as_string($CRLF);
}

1;
__END__

=head1 NAME

Socialtext::Async::HTTPD - AnyEvent HTTPD

=head1 SYNOPSIS

    my $done = AE::cv;
    my $s = http_server '127.0.0.1', 22222, sub {
        $done->begin;
        my $handle = shift;
        my $env = shift;
        my $content_ref = shift; # undef if none
        my $fatal_error = shift;
        my $error_string = shift;

        my $headers = HTTP::Headers->new(
            'Status' => '200 OK',
            'Content-Type' => 'text/plain',
            'Connection' => 'close',
        );

        $handle->push_write($headers->as_string . "\r\nHello World!\r\n");
        $handle->on_drain(sub {
            eval { $handle->destroy; }
            $done->end;
        });
    }
    $done->recv;

=head1 DESCRIPTION

This module is just for "porting" the JSON-proxy app we wrote.  Going forward,
we really should use PSGI and Plack.

Sets up an HTTP daemon on the specified port.  When a request has been
received in its entirety, it is passed through to the callback.

First param to the callback is an C<AnyEvent::Handle> object. Use this to
respond to the request.  It's your responsibility to destroy it properly.

The second param is a PSGI- and roughtly-SCGI-compatible C<%env> hash.  It
contains the usual suspects as far as CGI env vars go.

The third param is a reference to any POST/PUT body, undef otherwise.

Check the 4th and 5th params for errors.

=cut
