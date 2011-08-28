#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::More tests => 3;
use Socialtext::Cache;
use Socialtext::Cache::PersistentHash;

###############################################################################
# Persistent cache should *not* be clearable.
cannot_clear_persistent_cache: {
    my $cache = Socialtext::Cache->cache('test', {
        class => 'Socialtext::Cache::PersistentHash',
    } );
    isa_ok $cache, 'Socialtext::Cache::PersistentHash';

    my $key = 'foo';
    my $val = 'bar';
    $cache->set($key, $val);
    is $cache->get($key), $val, '... stored value in cache';
    $cache->clear();
    is $cache->get($key), $val, '... value *still* stored in cache';
}
