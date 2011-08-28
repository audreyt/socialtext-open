#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 13;

BEGIN {
    use_ok 'Socialtext::Handler::URIMap';
}

Single_map_file: {
    my $map = Socialtext::Handler::URIMap->new(
        config_dir => 't/test-data/uri-maps/single');
    my $uri_hooks = $map->uri_hooks;
    is ref($uri_hooks), 'ARRAY';
    is scalar(@$uri_hooks), 2;
    my $version_hook = $uri_hooks->[1]->{'/data/version'};
    ok $version_hook;
    ok $version_hook->{GET};
    ok $version_hook->{'*'};
}

Drop_in_uri_maps: {
    my $map = Socialtext::Handler::URIMap->new(
        config_dir => 't/test-data/uri-maps/drop-in');
    my $uri_hooks = $map->uri_hooks;
    is ref($uri_hooks), 'ARRAY';
    is scalar(@$uri_hooks), 4;
    ok $uri_hooks->[0]->{'/data/echo/:text'};
    ok $uri_hooks->[1]->{'/data/version'};
    ok $uri_hooks->[2]->{'/data/bar'};
    ok $uri_hooks->[3]->{'/data/foo'};
}

Missing_uri_map: {
    my $map = Socialtext::Handler::URIMap->new( config_dir => '/' );
    eval { $map->uri_hooks };
    like $@, qr/\QYAML Error: Couldn't open\E/;
}
