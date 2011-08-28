# @COPYRIGHT@
package Socialtext::User::Cache;
use strict;
use warnings;
use Socialtext::Cache;

our $Enabled = 0;
our %stats = (
    fetch  => 0,
    store  => 0,
    remove => 0,
);

my %ValidKeys = (
    user_id          => 1,
    email_address    => 1,
    username         => 1,
    driver_unique_id => 1,
);

sub Fetch {
    my ($class, $key, $val) = @_;
    return unless $Enabled;
    return unless $ValidKeys{$key};
    $stats{fetch}++;
    my $key_cache = Socialtext::Cache->cache("homunculus:$key");
    return $key_cache->get($val);
}

sub Store {
    my ($class, $key, $val, $homunculus) = @_;
    return unless $Enabled;
    return unless $ValidKeys{$key};

    # remove any old cache entries for the homunculus defined by the given
    # key/val pair
    my $old_homey = _resolve_homunculus($key, $val);
    if ($old_homey) {
        # localize the stats so that the "remove" action doesn't get counted
        local %stats = %stats;
        Socialtext::User::Cache->Remove($old_homey);
    }

    # proactively cache the homunculus against all valid keys, so he can be
    # found quickly/easily again in the future
    if ($homunculus) {
        $stats{store}++;
        foreach my $key (keys %ValidKeys) {
            my $cache = Socialtext::Cache->cache("homunculus:$key");
            $cache->set($homunculus->$key, $homunculus);
        }
    }
}

sub Remove {
    my $class = shift;
    return unless $Enabled;

    # accept either "key=>val" pair to lookup homunculus, or the homunculus
    # directly.
    my $homunculus = _resolve_homunculus(@_);
    return unless $homunculus;

    # remove the homunculus from all caches
    $stats{remove}++;
    foreach my $key (keys %ValidKeys) {
        my $cache = Socialtext::Cache->cache("homunculus:$key");
        $cache->remove($homunculus->$key);
    }
}

sub Clear {
    my $cache;
    foreach my $key (keys %ValidKeys) {
        $cache = Socialtext::Cache->cache("homunculus:$key");
        $cache->clear();
    }
}

sub ClearStats {
    map { $stats{$_} = 0 } keys %stats;
}

sub _resolve_homunculus {
    # if given a "key=>val" pair, use that to find the homunculus in the cache
    if (@_ > 1) {
        my ($key, $val) = @_;
        return unless $ValidKeys{$key};

        my $cache = Socialtext::Cache->cache("homunculus:$key");
        return $cache->get($val);
    }
    # only given one arg; must *be* the homunculus
    return $_[0];
}

1;
