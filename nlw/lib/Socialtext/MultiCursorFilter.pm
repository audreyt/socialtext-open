package Socialtext::MultiCursorFilter; # McFilter for short.
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';

has 'cursor' => (
    is => 'ro', isa => 'Socialtext::MultiCursor',
    required => 1,
    handles => [ qw(apply) ],
);

has 'filter' => (
    is => 'rw', isa => 'CodeRef',
    required => 1,
);

has 'limit' => (
    is => 'ro', isa => 'Int',
);

has 'offset' => (
    is => 'ro', isa => 'Int',
    default => 0,
);

has 'position' => (
    is => 'rw', isa => 'Int',
    default => 0,
);

sub _get_next_valid_item {
    my $self = shift;
    my $found = 0;

    my $item;
    do {
        $item = $self->cursor->next();
        return $item unless defined $item;

        $found = $self->filter->($item);
    } while (!$found);
    $self->increment;

    return $item;
}

sub next {
    my $self = shift;
    my $found = 0;
    my $item;

    return undef
        if $self->limit && $self->position >= $self->offset + $self->limit;

    while ($self->position <= $self->offset - 1) {
        $item = $self->_get_next_valid_item;
        return $item if !defined($item);
    }
    return $self->_get_next_valid_item;
}

sub increment {
    my $self = shift;
    $self->position($self->position + 1);
}

sub all {
    my $self = shift;
    my @results = ();

    while (my $item = $self->next()) {
        push @results, $item;
    };
    $self->reset;

    return @results;
}

sub reset {
    my $self = shift;
    $self->cursor->reset();
    $self->position(0);

    return $self;
}

sub count {
    my $self = shift;
    return scalar($self->all());
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::MultiCursorFilter - Filtering for a Socialtext::MultiCursor

=head1 SYNOPSIS

  use Socialtext::MultiCursor;
  use Socialtext::MultiCursorFilter;

  my $cursor = Socialtext::MultiCursor->new(
      iterables => [ $db_cursor, \@some_array ] 
  );

  my $mc_filter = Socialtext::MultiCursorFilter->new(
      cursor => $cursor,
      filter => sub { return shift eq 'something' },
  );

=head1 DESCRIPTION

This class provides a filter for a standard Socialtext::MultiCursor. It
presents an identical interface, but returns results based on whether or not
the 'filter' code returns true.

This is great for filtering results passed back from the DB as a
Socialtext::MultiCursor. It should be noted, though, that this can throw off
your limit/offsets, so those should be done here rather than in the DB.
