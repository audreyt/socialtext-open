# @COPYRIGHT@
package Socialtext::User::Cache;
use strict;
use warnings;
use Socialtext::Cache;

our $Enabled = 0;

my %ValidKeys = (
    user_id => 1,
    email_address => 1,
    username => 1,
);

sub Fetch {
    my ($class, $key, $val) = @_;
    return unless $Enabled;
    return unless $ValidKeys{$key};
    my $key_cache = Socialtext::Cache->cache("homunculus:$key");
    return $key_cache->get($val);
}

sub Store {
    my ($class, $key, $val, $user) = @_;
    return unless $Enabled;
    return unless $ValidKeys{$key};
    my $key_cache = Socialtext::Cache->cache("homunculus:$key");
    return $key_cache->set($val, $user);
}

sub MaybeStore {
    my ($class, $key, $val, $user) = @_;
    return unless $Enabled;
    return unless $ValidKeys{$key};
    my $key_cache = Socialtext::Cache->cache("homunculus:$key");
    if (!$key_cache->get($val)) {
        $key_cache->set($val, $user);
        return 1;
    }
    return;
}

sub Clear {
    my $cache;
    foreach my $key (keys %ValidKeys) {
        $cache = Socialtext::Cache->cache("homunculus:$key");
        $cache->clear();
    }
}

1;
