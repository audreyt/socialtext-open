#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 17;
use File::Temp qw/tempdir/;

my $gen_config = "dev-bin/gen-config";
ok -x $gen_config;

my $test_root = tempdir( CLEANUP => 1 );

Usage: {
    # NOTE: this usage test is really only valid for a non-dev environment
    # when running in a dev-environment, which is what a fresh-dev-env-from-scratched
    # world is going to look like, the usage error won't get spewed from gen-config.
    # Now that we don't re-gen the configuration on every test, the fact that we are
    # in a dev environment is being remembered in Socialtext::Build::ConfigureValues.pm
    # for us so we need to override that setting in order to produce the error.
    my $output = run_test('--dev=0');
    like $output, qr/\QNot run with --sitewide, and no --root dir parameter given.\E/;
}

Dev_env: {
    my $output = run_test("--root $test_root --dev=0");
    my @files = qw(
        nginx/nlw-nginx-live.conf
        nginx/mime.conf
        nginx/proxy.conf
        nginx/auto-generated.d/nlw.conf
        socialtext/shortcuts.yaml
        socialtext/uri_map.yaml
        socialtext/auth_map.yaml
    );
    for my $f (@files) {
        my $full_path = "$test_root/etc/$f";
        like $output, qr#\Q$full_path\E#;
        ok -e $full_path, "$full_path exists";
    }

    check_apache_config(
        MinSpareServers     => 1,
        MaxSpareServers     => 1,
        StartServers        => 1,
        MaxClients          => 3,
        MaxRequestsPerChild => 1000,
    );
}

Appliance: {
    $ENV{ST_MEMTOTAL} = 8000000;    # triggering use of Appliance settings
    run_test("--root $test_root --dev=0");
    check_apache_config(
        MinSpareServers     => 2,
        MaxSpareServers     => 4,
        StartServers        => 3,
        MaxClients          => 18,
        MaxRequestsPerChild => 1000,
    );
}

Quiet: {
    my $output = run_test("--quiet --root $test_root --dev=0");
    ok !$output;
}

exit;

sub check_apache_config {
    return; # No longer applicable to nlw-psgi

    my %attr = @_;

    open CONF, "$test_root/etc/apache-perl/nlw-httpd.conf";
    my $lines = join "\n", <CONF>;
    close CONF;

    for my $key ( keys %attr ) {
        like $lines, qr($key\s+$attr{$key}\s), "Checking $key";
    }
}

sub run_test {
    my $args = shift;
    my $output = qx($^X $gen_config $args 2>&1);
#    warn $output;
    return $output;
}
