package Socialtext::List;
use warnings;
use strict;
# @COPYRIGHT@

=head1 NAME

Socialtext::List - List utility functions

=head1 SYNOPSIS

    use Socialtext::List qw/rand_subset rand_pick/;
    my @sub = rand_subset @list, $k;
    my $item = rand_pick @list;

=head1 DESCRIPTION

Some list utility functions.

The random functions use perl's built-in C<rand()> for randomness.

=head1 FUNCTIONS

=over

=cut

use List::Util qw/shuffle/;
use base 'Exporter';
our $VERSION = 1.0;
our @EXPORT = ();
our @EXPORT_OK = qw(rand_subset rand_pick);

=item rand_subset @list, $k

Select k elements at random from the supplied list.  Uses a randomized
algorithm for small values of k (k <= 5% of list size).  Does not alter the
list.

=cut

sub rand_subset (\@$) {
    my ($list, $k) = @_;

    return shuffle @$list if ($k >= @$list);

    # if selecting more than 5% of the list just use the XS-accelerated
    # List::Util::shuffle
    if ($k / @$list > 0.05) {
        return (shuffle @$list)[0 .. $k-1];
    }

    # Use a vector to randomly select k sparse elements, using a bit vector to
    # keep track of already selected elements.  About 15% faster than shuffle
    # for a k that's 5% of the list size, getting faster as k decreases.
    my $vec = '';
    my @new = ();
    $#new = $k-1; # preallocate space
    my $i = 0;
    my $r;
    while ($i < $k) {
        do { $r = rand(@$list) } while (vec($vec, $r, 1));
        vec($vec, $r, 1) = 1;
        $new[$i++] = $list->[$r];
    }
    return @new;
}

=item rand_pick @list

Return a random element from the list.

=cut

sub rand_pick (\@) {
    $_[0][rand(scalar(@{$_[0]}))];
}

=back

=cut

1;

