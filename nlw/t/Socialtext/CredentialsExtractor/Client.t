#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 10;
use Test::Socialtext::Async;
use Test::Socialtext::Cookie;
use Socialtext::CredentialsExtractor::Client::Sync;

fixtures(qw( db ));

###############################################################################
# TEST: Cache valid credentials
cache_valid_credentials: {
    my $user    = create_test_user();
    my $user_id = $user->user_id;
    my $cookie  = Test::Socialtext::Cookie->BuildCookie(user_id => $user_id);
    my %env     = (
        HTTP_COOKIE => $cookie,
    );

    # Start UserD on a custom port
    my $st_userd = "$ENV{ST_CURRENT}/nlw/bin/st-userd";
    die "userd script is not executable" unless -x $st_userd;

    my $port = empty_port();
    diag "starting st-userd on port $port with script $st_userd";
    my $pid = fork_off($st_userd, "--port", $port);

    wait_until_pingable($port, 'userd');
    wait_until_pingable($port, 'userd');

    # Create a Creds Extraction client.
    my $client = Socialtext::CredentialsExtractor::Client::Sync->new(
        userd_port => $port,
    );
    my $stats;

    # Extract creds, check that the results got cached correctly
    $client->extract_credentials(\%env);
    $stats = $client->cache->stats;
    is $stats->{miss}, 1, 'Initial lookup was a cache miss';

    $client->extract_credentials(\%env);
    $stats = $client->cache->stats;
    is $stats->{hit}, 1, 'Subsequent lookup was a cache hit';

    sleep 3;
    $client->extract_credentials(\%env);
    $stats = $client->cache->stats;
    is $stats->{hit}, 2, 'Cache still valid after sleeping';

    # Create a *NEW* Creds Extraction client; should *still* be cached
    $client = Socialtext::CredentialsExtractor::Client::Sync->new(
        userd_port => $port,
    );
    $client->extract_credentials(\%env);
    $stats = $client->cache->stats;
    is $stats->{hit}, 3, 'Cached even with new creds extraction client';

    # CLEANUP
    kill_kill_pid($pid);
}
