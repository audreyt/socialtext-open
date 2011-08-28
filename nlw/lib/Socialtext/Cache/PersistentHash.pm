package Socialtext::Cache::PersistentHash;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(Socialtext::Cache::Hash);

# You can't clear this cache. :p
sub clear { }

1;

=head1 NAME

Socialtext::Cache::PersistentHash - Persistent in-memory cache

=head1 SYNOPSIS

  use Socialtext::Cache;

  $cache = Socialtext::Cache->cache('my-named-cache', {
      class => 'Socialtext::Cache::PersistentHash',
  } );

=head1 DESCRIPTION

This module implements a I<persistent> in-memory hash.  You can put things in,
but the cache B<is not> clearable.

=cut
