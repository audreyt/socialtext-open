# @COPYRIGHT@
package Socialtext::Statistic;
use warnings;
use strict;

sub new {
    my $class = shift;

    my $self = bless {}, $class;
    $self->_initialize;
    return $self;
}

sub _initialize {
    my $self = shift;

    $self->{len}    = 0;
    $self->{sum}    = 0;
    $self->{sum_sq} = 0;
}

sub len { $_[0]->{len} }
sub min { exists $_[0]->{min} ? $_[0]->{min} : '' }
sub max { exists $_[0]->{max} ? $_[0]->{max} : '' }

sub observe {
    my $self = shift;
    my $x = shift;

    ++$self->{len};
    $self->{sum}    += $x;
    $self->{sum_sq} += $x * $x;

    $self->{min} = $x unless exists $self->{min} and $x > $self->{min};
    $self->{max} = $x unless exists $self->{max} and $x < $self->{max};
}

sub mean {
    my $self = shift;

    return ( $self->len > 1 ) ? $self->{sum} / $self->len : $self->{sum};
}

sub variance {
    my $self = shift;

    if ($self->len > 1) {
        my $mean = $self->mean;
        return ( $self->{sum_sq} - $self->len * $mean * $mean )
            / ( $self->len - 1 );
    }
    return 0;
}

1;

__END__

=head1 DESCRIPTION

Socialtext::Statistic - Base class for any statistic we wish to gather compactly.

=head1 SYNOPSIS

package Socialtext::MyStat;

use base 'Socialtext::Statistic';

# ...

package main;

my $stat = Socialtext::MyStat;

LOOP: while (...) {
    # ...
    $stat->observe($observation);

}

print "MyStat: mean ", $stat->mean, " variance ", $stat->variance, "\n";


1;

__END__
=head1 OBJECT METHODS

=over 4

=item $stat->observe($observation);

=item $stat->len();

=item $stat->mean();

=item $stat->variance();

=item $stat->min();

=item $stat->max();

=back

=head1 AUTHOR

Socialtext, Inc., <code@socialtext.com>

=head1 COPYRIGHT & LICENSE

Copyright 2005 Socialtext, Inc., All Rights Reserved.

