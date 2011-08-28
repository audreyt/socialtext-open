#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 2;
use Socialtext::AppConfig;
use File::Temp qw(tempdir);

fixtures(qw( base_config destructive ));

###############################################################################
# TEST: when ssl_only=1 and there's no SSL cert available, it should die
ssl_only_without_certs: {
    # Turn on "ssl_only=1"
    my $appconfig = Socialtext::AppConfig->new();
    $appconfig->set(ssl_only => 1);
    $appconfig->write();

    # Remove any existing SSL certs
    my $base_dir = Test::Socialtext::Environment->instance->base_dir;
    my $cert_dir = File::Spec->catdir($base_dir, 'etc/ssl/certs');
    unlink( <$cert_dir/*> );
    my @certs = <$cert_dir/*>;
    ok !@certs, 'SSL certs removed from test environment';

    # Run gen-config, and expect it to choke
    my $test_root = tempdir(CLEANUP => 1);
    my $output = qx($^X dev-bin/gen-config --root $test_root --dev=0 2>&1);
    like $output, qr/SSL only, but no SSL certificate found/i,
        'gen-config (expectedly) fails; SSL-only but no SSL cert available';
}
