package Socialtext::Cache;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Cache::Hash;

# if we ever forget to clear, make sure that caches auto-purge periodically.
our $DefaultExpiresIn = '1m';

# cache class used
our $CacheClass = 'Socialtext::Cache::Hash';

# keep track of named caches we've instantiated; its faster that way.
our %CACHES;

sub cache {
    my ($class, $name, $opts) = @_;
    $opts ||= { };

    unless ($CACHES{$name}) {
        # Figure out which cache class we need
        my $cache_class = $opts->{class} || $CacheClass;
        eval "require $cache_class";
        if ($@) {
            die "Unable to load cache class '$cache_class'; $@";
        }

        # Instantiate the cache
        $CACHES{$name} = $cache_class->new( {
            namespace           => $name,
            default_expires_in  => $DefaultExpiresIn,
            auto_purge_on_get   => 1,
            } );
    }

    return $CACHES{$name};
}

sub clear {
    my ($class, $name) = @_;
    if ($name) {
        my $cache = $class->cache($name);
        $cache->clear()
    }
    else {
        map { $_->clear() } values %CACHES;
    }
}

sub stats {
    my %stats;
    while (my ($name, $cache) = each %CACHES) {
        if ($cache->can('stats')) {
            $stats{$name} = $cache->stats();
        }
    }
    return \%stats;
}

1;

=head1 NAME

Socialtext::Cache - In-memory named caches

=head1 SYNOPSIS

  # get a named cache, and interact with it
  $cache = Socialtext::Cache->cache('user_id');

  $user_id_rec = $cache->get($user_id);
  $cache->set($user_id, $user_id_rec);

  # clear/flush a cache by its handle
  $cache->clear();

  # clear/flush a cache by its name
  Socialtext::Cache->clear('user_id');

  # clear/flush *all* named caches
  Socialtext::Cache->clear();

  # get instrumentation stats on all caches
  $stats = Socialtext::Cache->stats();

=head1 DESCRIPTION

C<Socialtext::Cache> implements a single point of entry for a series of named
in-memory caches.

Need a cache somewhere?  Just create a new one and start using it.

Worried about dangling caches?  Don't; C<Socialtext::Cache->clear()> will be
called at the end of the HTTP request, and all of the caches will be flushed
automatically.

Your only concern should be using the cache to help speed things up where
caching will be effective.

Further, B<don't> be concerned with trying to keep the cache up-to-date when
things change, B<just clear the whole cache and be done with it>.  Brutal?
Yes.  Easier than trying to keep the cache coherent in the face of any
possible change?  Yes.

Is a plain old hash faster?  Probably.  Is a hash better?  Maybe.  If you use
C<Socialtext::Cache>, though, and we later find that switching to a shared
memory cache or a file cache provides better re-use or increases the hit
ratio, you'll get all that benefit for free.

=head1 METHODS

=over

=item B<Socialtext::Cache-E<gt>cache($name, $opts)>

Retrieves the given named cache object.  Its created automatically if it
doesn't already exist.

An optional hash-ref of C<$opts> can be used to specify other cache creation
options:

=over

=item class

Name of the underlying caching driver to use.  Defaults to
C<Socialtext::Cache::Hash> unless explicitly provided.

=back

=item B<Socialtext::Cache-E<gt>clear($name)>

Clears the given named cache, removing B<all> entries from the cache.

If no C<$name> is provided, this method clears B<ALL> of the caches.

=item B<Socialtext::Cache-E<gt>stats()>

Returns a hash-ref of instrumentation data on all of the named caches that are
in use.

=back

=head1 AUTHOR

Socialtext, Inc.  C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Cache::Cache>.

=cut
