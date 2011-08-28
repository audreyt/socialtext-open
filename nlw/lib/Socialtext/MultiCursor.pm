package Socialtext::MultiCursor;
use warnings;
use strict;

use Class::Field 'field';
use List::Util 'sum';

field 'iterables';
field 'apply';
field 'current_iterable';
field 'current_iterable_index';

sub new {
    my $class = shift;
    my %p = @_;

    my $self = bless {}, $class;
    $self->iterables([]);
    $self->current_iterable(0);
    $self->current_iterable_index(0);

    $self->apply($p{apply});
    $self->add_iterable($_) for @{ $p{iterables} };

    return $self;
}

sub add_iterable {
    my ( $self, $iterable ) = @_;

    push @{$self->iterables}, $iterable;
}

sub all {
    my ($self) = @_;

    my @flatttened = map { $self->_all_rows($_) } @{ $self->iterables };
    return ( $self->apply )
        ? grep { defined } map { $self->apply->($_) } @flatttened
        : @flatttened;
}

sub _all_rows {
    my ($self, $iterable) = @_;

    return (ref $iterable eq 'ARRAY') 
        ? @$iterable 
        : ( ref $iterable  )
            ? $iterable->all_rows
            : $iterable;
}

{
    no warnings 'once';
    *all_rows = *all;
}

sub reset {
    my ( $self ) = @_;

    $self->current_iterable(0);
    $self->current_iterable_index(0);

    foreach my $iterable (@{$self->iterables}) {
        $iterable->reset unless ref $iterable eq 'ARRAY' or ! ref $iterable;
    }
    return $self;
}

sub count {
    my ( $self ) = @_;

    return sum(map { $self->_count($_) } @{$self->iterables}) || 0;
}

sub _count {
    my ( $self, $iterable ) = @_;

    return ref $iterable eq 'ARRAY' 
        ? scalar @$iterable  
        : ( ref $iterable )
            ? $iterable->count
            : 1;
}

sub next {
    my ( $self ) = @_;

    my $i = $self->current_iterable;
    my $iter = $self->iterables->[$i];

    my $next = $self->_next($iter);

    if (defined $next) {
        return (defined $self->apply) 
            ? $self->apply->($next) || $self->next
            : $next;
    }
    else {
        if ($i >= $#{$self->iterables}) {
            return undef;
        }
        else {
            $self->current_iterable($i + 1);
            $self->current_iterable_index(0);
            return $self->next;
        }
    }
}

sub _next {
    my ( $self, $iterable ) = @_;

    if (ref $iterable eq 'ARRAY') {
        my $index = $self->current_iterable_index;
        $self->current_iterable_index($index + 1);

        return ( $index > $#$iterable 
            ? undef 
            : $iterable->[$index]);
    }
    elsif (ref $iterable) {  # assume it's an object
        my @next = $iterable->next;

        return (@next > 1 
            ? [@next] 
            : $next[0]);
    }
    else {
        $self->current_iterable( $self->current_iterable + 1 );
        return $iterable || undef;
    }
}

# REVIEW: This is very minimally done, and so far only supports the
# use case of List All Users
sub next_as_hash {
    my $self = shift;
    my $next = $self->next or return;

    return map { defined $_ ? ( $self->_name_for($_) => $_ ) : () }
      ( ref $next ) eq 'ARRAY' ? @$next : $next;
}

sub _name_for {
    my $self = shift;
    my @parts = split /::/, ref shift;
    return lc $parts[-1];
}

1;

__END__

=head1 NAME

Socialtext::MultiCursor - An aggregating Iterator object

=head1 SYNOPSIS

  use Socialtext::MultiCursor;

  my $cursor = Socialtext::MultiCursor->new(
      iterables => [ $db_cursor, \@some_array ] 
  );

  my $applied_cursor = Socialtext::MultiCursor->new(
      iterables => [ $cursor ],
      apply     => sub {
          my $element = shift;
          return transform_on( $element );
      }
  );

=head1 DESCRIPTION

This class provides a means of aggregating over one or more iterable
objects, with a unified interface for accessing elements in one
direction, sequentially.

=head1 METHODS

=head2 Socialtext::MultiCursor->new(PARAMS)

Instantiate a C<Socialtext::MultiCursor> object, with one or more
iterables, and an optional 'apply' function which will be applied to
each element as it's fetched via 'next' or 'all'.

PARAMS can include:

=over 4

=item * iterables - required

=item * apply - optional

=back

=head2 $cursor->add_iterable( $iterable )

Add an iterable object (cursor-type or array reference) to our list of
iterables.

=head2 $cursor->all()

Return a flattened array of all elements from all iterables, applying
'apply' function to each element, if necessary.

=head2 $cursor->all_rows()

Alias for all() - harkens back to Alz-abo Cursor origins.

=head2 $cursor->reset()

Reset the counters for our iterables (current iterable and current iterable
index both drop to 0).

=head2 $cursor->count()

Return the sum of the counts of all iterables.

=head2 $cursor->next()

Return the next element, applying 'apply' function to the element, if
necessary.

=head2 $cursor->next_as_hash()

Return the next element as a hash with keys being the table/class name
of the object, and the values being the object(s).

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., All Rights Reserved.

=cut

