# @COPYRIGHT@
package Socialtext::Statistic::CpuTime;
use warnings;
use strict;

use base 'Socialtext::Statistic';

sub tic {
    my $self = shift;

    $self->{tic} = _get_cpu_time();
}

sub toc {
    my $self = shift;

    $self->observe(_get_cpu_time() - $self->{tic});
}

sub _get_cpu_time {
    my @times = times;

    return $times[0] + $times[1];
}

1;

__END__

=head1 OBJECT METHODS

=head2 $et->tic();

Start counting CPU time.

=head2 $et->toc();

Record consumed CPU time since last tic() as an observation.  (Floating point
seconds.)

=head1 SEE ALSO

Socialtext::Statistic
