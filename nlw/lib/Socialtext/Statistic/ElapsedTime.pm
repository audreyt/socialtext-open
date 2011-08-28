# @COPYRIGHT@
package Socialtext::Statistic::ElapsedTime;
use warnings;
use strict;

use base 'Socialtext::Statistic';

use Time::HiRes 'time';

sub tic {
    my $self = shift;

    $self->{tic} = time;
}

sub toc {
    my $self = shift;

    $self->observe(time - $self->{tic});
}

1;

__END__

=head1 OBJECT METHODS

=head2 $et->tic();

Start counting elapsed time.

=head2 $et->toc();

Record elapsed time since last tic() as an observation.  (Floating point
seconds.)

=head1 SEE ALSO

Socialtext::Statistic
