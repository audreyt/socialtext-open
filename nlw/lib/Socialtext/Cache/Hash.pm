package Socialtext::Cache::Hash;

use strict;
use warnings;

our %stats;

sub new {
    my $class = shift;
    my $self  = { };
    bless $self, $class;
}

sub get {
    my ($self, $key) = @_;
    exists $self->{$key} ? $stats{$self}{hit}++ : $stats{$self}{miss}++;
    return $self->{$key};
}

sub set {
    my ($self, $key, $val) = @_;
    $stats{$self}{set}++;
    $self->{$key} = $val;
}

sub remove {
    my ($self, $key) = @_;
    $stats{$self}{remove}++;
    delete $self->{$key};
}

sub get_keys {
    my $self = shift;
    return keys %{$self};
}

sub clear {
    my $self = shift;
    map { delete $self->{$_} } $self->get_keys();
}

sub stats {
    my $self = shift;
    return $stats{$self};
}

1;

=head1 NAME

Socialtext::Cache::Hash - In memory "hash" cache implementation

=head1 DESCRIPTION

C<Socialtext::Cache::Hash> implements an in-memory "hash" implementation of a
cache, that provides a C<Cache::Cache> interface for usage.

Its actually B<just> a get/set wrapper around a regular hash, B<NO>
marshalling of objects/data is done whatsoever (unlike C<Cache::MemoryCache>,
which uses C<Storable> to clone all objects when they're added to the cache).
As a result, we should be significantly faster, but it B<does> mean that
you're getting back the I<exact same> object that you put in the cache and not
a clone/copy of it.

Further, C<Socialtext::Cache::Hash> makes B<NO> attempts to implement any
cache expiry mechanism.  You put something in the cache, its there, period.

Plain, simple, and fast.  And, when we eventually decide to switch it out for
something more robust from the C<Cache::Cache> distribution, we shouldn't have
to make a big effort to port/migrate things; they'll already be using the
get/set methods.

=head1 METHODS

=over

=item B<Socialtext::Cache::Hash-E<gt>new(\%options)>

Creates a new cache object.  Although we accept a hash-ref of options (just
like any other C<Cache::Cache> like interface), we don't actually use any of
them; they're silently ignored.

=item B<get($key)>

Retrieves the data item previously stored against the given C<$key>.

=item B<set($key, $val)>

Stores the data item C<$val> against the given C<$key>.

=item B<remove($key)>

Removes the data item previously stored against the given C<$key>.

=item B<get_keys()>

Returns an unsorted list of the keys in this cache.

=item B<clear()>

Clears the cache, flushing it entirely of all keys/values.

=back

=head1 AUTHOR

Graham TerMarsch C<< <graham.termarsch@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2008 Socialtext, Inc., All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

C<Socialtext::Cache>,
C<Cache::Cache>.

=cut
