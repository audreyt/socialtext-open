package Socialtext::Functional;
# @COPYRIGHT@

use warnings;
use strict;

=head1 NAME

Socialtext::Functional - Assorted functional-style routines.

=cut

use base 'Exporter';

our ( $a, $b );
our @EXPORT_OK = qw(hgrep foldr sum);

=head1 FUNCTIONS

=head2 hgrep

This works just like C<grep> on a hash.  Instead of your routine seeing a
local value for C<$_>, it gets local values for package globals C<$k> and
C<$v>, much as C<sort> produces local values for package globals C<$a> and
C<$b>.

In order to elide warnings, you probably want to say C<our ( $k, $v )> in files which use C<hgrep>.

=cut

sub hgrep(&@) {
    my ( $sub, %hash ) = @_;
    my %result;
    my $pkg = (caller)[0];

    no strict 'refs';
    while (local ( ${"$pkg\::k"}, ${"$pkg\::v"} ) = each %hash) {
        $result{${"$pkg\::k"}} = ${"$pkg\::v"} if &$sub;
    }
    return %result;
}

=head2 

=head1 EXAMPLES

    my %public_hash = hgrep { $k ne 'password' } %{ $user->to_hash };

=cut

1;
