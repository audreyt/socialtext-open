package Test::LWP::UserAgent::keep_alive;
# @COPYRIGHT@

use strict;
use warnings;
use base qw(LWP::UserAgent);

sub new {
    my $class = shift;
    return $class->SUPER::new(keep_alive=>1, $class);
}

1;

=head1 NAME

Test::LWP::UserAgent::keep_alive - LWP::UserAgent with Keep-Alives enabled

=head1 SYNOPSIS

  {
      local $Test::HTTP::UaClass = 'Test::LWP::UserAgent::keep_alive';
      ...
  }

=head1 DESCRIPTION

C<Test::LWP::UserAgent::keep_alive> implements a derived C<LWP::UserAgent>
with Keep-Alive connections enabled by default.

This class was created solely for use when running tests with C<Test::HTTP>;
although it I<may> have uses elsewhere, its primary purpose is for explicit
testing of Keep-Alive HTTP requests.

=head1 METHODS

=over

=item B<new()>

Creates a new C<LWP::UserAgent> object, with Keep-Alive requests enabled.

=back

=head1 SEE ALSO

L<LWP::UserAgent>,
L<Test::HTTP>.

=cut
