#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 12;
use Socialtext::HTTP::Ports qw(:constants);

###############################################################################
# Fixtures: base_config
# - need the config files laid out, but don't care what's in them
fixtures(qw( base_config ));

###############################################################################
# SANITY CHECK: ST::AppConfig thinks we're in a dev-env (the default)
ok !Socialtext::AppConfig->is_appliance(), 'sanity check; running in a dev-env, not an appliance';

###############################################################################
# TEST: default dev-env back-end HTTP port
default_devenv_backend_http_port: {
    my $port     = Socialtext::HTTP::Ports->backend_http_port();
    my $expected = PORTS_START_AT() + BACKEND_PORT_DIFFERENCE() + $>;
    is $port, $expected, 'default dev-env backend HTTP port';
}

###############################################################################
# TEST: default dev-env back-end HTTPS port
default_devenv_backend_https_port: {
    my $port     = Socialtext::HTTP::Ports->backend_https_port();
    my $expected = PORTS_START_AT() + BACKEND_PORT_DIFFERENCE() + $>;
    is $port, $expected, 'default dev-env backend HTTPS port';
}

###############################################################################
# TEST: default dev-env front-end HTTP port
default_devenv_http_port: {
    my $port     = Socialtext::HTTP::Ports->http_port();
    my $expected = PORTS_START_AT() + $>;
    is $port, $expected, 'default dev-env HTTP port';
}

###############################################################################
# TEST: default dev-env front-end HTTPS port
default_devenv_https_port: {
    my $port     = Socialtext::HTTP::Ports->https_port();
    my $expected = PORTS_START_AT() + SSL_PORT_DIFFERENCE() + $>;
    is $port, $expected, 'default dev-env HTTPS port';
}

###############################################################################
# TEST: default appliance backend HTTP port
default_appliance_backend_http_port: {
    local $ENV{NLW_IS_APPLIANCE} = 1;
    my $port     = Socialtext::HTTP::Ports->backend_http_port();
    my $expected = STANDARD_BACKEND_PORT();
    is $port, $expected, 'default appliance backend HTTP port';
}

###############################################################################
# TEST: default appliance backend HTTPS port
default_appliance_backend_https_port: {
    local $ENV{NLW_IS_APPLIANCE} = 1;
    my $port     = Socialtext::HTTP::Ports->backend_https_port();
    my $expected = STANDARD_BACKEND_PORT();
    is $port, $expected, 'default appliance backend HTTPS port';
}

###############################################################################
# TEST: default appliance front-end HTTP port
default_appliance_http_port: {
    local $ENV{NLW_IS_APPLIANCE} = 1;
    local $ENV{NLW_APPCONFIG} = 'custom_http_port=0';

    my $port     = Socialtext::HTTP::Ports->http_port();
    my $expected = STANDARD_HTTP_PORT();
    is $port, $expected, 'default appliance HTTP port';
}

###############################################################################
# TEST: default appliance front-end HTTPS port
default_appliance_https_port: {
    local $ENV{NLW_IS_APPLIANCE} = 1;
    local $ENV{NLW_APPCONFIG} = 'ssl_port=0';

    my $port     = Socialtext::HTTP::Ports->https_port();
    my $expected = STANDARD_HTTPS_PORT();
    is $port, $expected, 'default appliance HTTPS port';
}

###############################################################################
# TEST: configured front-end HTTP port
configured_http_port: {
    my $expected = 12345;
    Socialtext::AppConfig->set(custom_http_port => $expected);

    my $port = Socialtext::HTTP::Ports->http_port();
    is $port, $expected, 'custom configured HTTP port';
}

###############################################################################
# TEST: configured front-end HTTPS port
configured_https_port: {
    my $expected = 98765;
    Socialtext::AppConfig->set(ssl_port => $expected);

    my $port = Socialtext::HTTP::Ports->https_port();
    is $port, $expected, 'custom configured HTTPS port';
}

###############################################################################
# TEST: env var override for front-end HTTP port
env_var_override_http_port: {
    my $expected = 456789;
    local $ENV{NLW_FRONTEND_PORT} = $expected;

    my $port = Socialtext::HTTP::Ports->http_port();
    is $port, $expected, 'env var override for HTTP port';
}
