#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use mocked 'Apache::Request';
use mocked 'Apache::Constants', qw(REDIRECT FORBIDDEN);
use Socialtext::HTTP::Ports;
use Test::Socialtext tests => 10;

use_ok 'Socialtext::Handler::Redirect';

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it
fixtures(qw( db ));

###############################################################################
# We *only* need a simple credentials extractor for these tests, which means
# less test setup (as we don't need to set things up to handle all of the
# possible creds extractors that could be configured.
Socialtext::AppConfig->set(credentials_extractors => 'Guest');

###############################################################################
# TEST: Redirect defaults to "/"
redirect_defaults_to_slash: {
    my $mock_request = Apache::Request->new(uri => '/r');
    my $response     = Socialtext::Handler::Redirect->handler($mock_request);

    is $response, REDIRECT(), 'redirect response';
    is $mock_request->{Location}, '/', '... default redirection; "/"';
}

###############################################################################
# TEST: Redirect to relative URI
redirect_to_relative_uri: {
    my $uri = '/foo';

    local $Apache::Request::PARAMS{redirect_to} = $uri;
    my $mock_request = Apache::Request->new(uri => '/r');
    my $response     = Socialtext::Handler::Redirect->handler($mock_request);

    is $response, REDIRECT(), 'redirect response';
    is $mock_request->{Location}, $uri, '... relative URI redirect';
}

###############################################################################
# TEST: Redirect to absolute URI on *same* machine is ok
redirect_to_local_absolute_uri_ok: {
    my $host    = Socialtext::AppConfig->web_hostname();
    my $port    = Socialtext::HTTP::Ports->http_port();
    my $uri     = "/foo";
    my $abs_uri = "http://$host\:$port$uri";

    local $Apache::Request::PARAMS{redirect_to} = $abs_uri;
    my $mock_request = Apache::Request->new(uri => '/r');
    my $response     = Socialtext::Handler::Redirect->handler($mock_request);

    is $response, REDIRECT(), 'redirect response';
    is $mock_request->{Location}, $uri, '... redirect to local absolute URI';
}

###############################################################################
# TEST: Redirect to absolute URI *off* box is forbidden
redirect_to_offsite_absolute_uri_forbidden: {
    my $host    = Socialtext::AppConfig->web_hostname();
    my $abs_uri = 'http://www.google.com/codesearch';

    clear_log();
    local $Apache::Request::PARAMS{redirect_to} = $abs_uri;
    my $mock_request = Apache::Request->new(uri => '/r');
    my $response     = Socialtext::Handler::Redirect->handler($mock_request);

    is $response, FORBIDDEN(), 'external redirect forbidden';
    my $logged = dump_log;
    like $logged, qr/\(debug\).*redirect/;
    like $logged, qr/\(error\).*redirect attempted to external/,
        "... and logged an appropriate error";
}
