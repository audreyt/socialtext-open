#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 11;
use Socialtext::Cache;
use Socialtext::AppConfig;
use Socialtext::URI;

# Create a config file to test with/against
my $config_file = Test::Socialtext->setup_test_appconfig_dir();
my $appconfig   = Socialtext::AppConfig->new(file => $config_file);

# Figure out what the hostname is we should expect in the results
my $hostname = $appconfig->web_hostname();

###############################################################################
# TEST: URI generation with explicit path
uri_with_path: {
    local $ENV{NLW_IS_APPLIANCE} = 1;   # pretend to be on an appliance

    my $path     = '/foo/bar';
    my $uri      = Socialtext::URI::uri(path => $path);
    my $expected = "http://$hostname$path";

    is $uri, $expected, 'URI with path';
}

###############################################################################
# TEST: URI generation with no path
uri_without_path: {
    local $ENV{NLW_IS_APPLIANCE} = 1;   # pretend to be on an appliance

    my $uri      = Socialtext::URI::uri();
    my $expected = "http://$hostname/";

    is $uri, $expected, 'URI without path';
}

###############################################################################
# TEST: URI generation with path and query
uri_with_path_and_query: {
    local $ENV{NLW_IS_APPLIANCE} = 1;   # pretend to be on an appliance

    my $path     = '/foo/bar';
    my $uri      = Socialtext::URI::uri(path => $path, query => { foo => 1 } );
    my $expected = "http://$hostname$path?foo=1";

    is $uri, $expected, 'URI with path';
}

###############################################################################
# TEST: Standard appliance HTTP URI doesn't end with ":80" (standard port)
appliance_http_uri_no_default_port_number: {
    local $ENV{NLW_IS_APPLIANCE} = 1;   # pretend to be on an appliance

    my $uri = Socialtext::URI::uri();
    my $expected = "http://$hostname/";
    is $uri, $expected, "appliance HTTP URI doesn't end with default port";
}

###############################################################################
# TEST: Standard appliance HTTPS URI doesn't end with ":443" (standard port)
appliance_https_uri_no_default_port_number: {
    local $ENV{NLW_IS_APPLIANCE} = 1;   # pretend to be on an appliance
    local $ENV{MOD_PERL} = 1;           # pretend to be under Mod_Perl
    local $ENV{NLWHTTPSRedirect} = 1;   # pretend to be HTTPS configured

    my $uri = Socialtext::URI::uri();
    my $expected = "https://$hostname/";
    is $uri, $expected, "appliance HTTPS URI doesn't end with default port";
}

###############################################################################
# TEST: Standard dev-env HTTP URI ends with ":<port>"
devenv_http_uri_has_port_number: {
    my $uri  = Socialtext::URI::uri();
    my $port = Socialtext::HTTP::Ports->http_port();
    my $expected = "http://$hostname\:$port/";
    is $uri, $expected, "dev-env HTTP URI ends with port number";
}

###############################################################################
# TEST: Standard dev-env HTTPS URI ends with ":<port>"
devenv_https_uri_has_port_number: {
    local $ENV{MOD_PERL} = 1;           # pretend to be under Mod_Perl
    local $ENV{NLWHTTPSRedirect} = 1;   # pretend to be HTTPS configured

    my $uri  = Socialtext::URI::uri();
    my $port = Socialtext::HTTP::Ports->https_port();
    my $expected = "https://$hostname\:$port/";
    is $uri, $expected, "dev-env HTTPS URI ends with port number";
}

###############################################################################
# TEST: ENV var can be used to over-ride ":<port>" on HTTP URI
env_var_override_http_port_number: {
    local $ENV{NLW_FRONTEND_PORT} = 1234;

    my $uri  = Socialtext::URI::uri();
    my $port = $ENV{NLW_FRONTEND_PORT};
    my $expected = "http://$hostname\:$port/";
    is $uri, $expected, "ENV var can over-ride port number on HTTP URI";
}

###############################################################################
# TEST: Custom config can be used to over-ride ":<port>" on HTTP URI
config_override_http_port_number: {
    Socialtext::AppConfig->set(custom_http_port => 9876);

    my $uri  = Socialtext::URI::uri();
    my $port = Socialtext::AppConfig->custom_http_port();
    my $expected = "http://$hostname\:$port/";
    is $uri, $expected, "config can over-ride port number on HTTP URI";
}

###############################################################################
# TEST: Custom config can be used to over-ride ":<port>" on HTTPS URI
config_override_https_port_number: {
    local $ENV{MOD_PERL} = 1;           # pretend to be under Mod_Perl
    local $ENV{NLWHTTPSRedirect} = 1;   # pretend to be HTTPS configured
    Socialtext::AppConfig->set(ssl_port => 56789);

    my $uri  = Socialtext::URI::uri();
    my $port = Socialtext::AppConfig->ssl_port();
    my $expected = "https://$hostname\:$port/";
    is $uri, $expected, "config can over-ride port number on HTTPS URI";
}

###############################################################################
# TEST: URI generation when "ssl_only" is enabled
ssl_only_forces_https_urls: {
    Socialtext::AppConfig->set(ssl_only => 1);
    Socialtext::AppConfig->set(ssl_port => 12345);

    my $uri  = Socialtext::URI::uri();
    my $port = Socialtext::AppConfig->ssl_port();
    my $expected = "https://$hostname\:$port/";
    is $uri, $expected, "enabling 'ssl_only' forces HTTPS URI generation";
}
