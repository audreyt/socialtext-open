# @COPYRIGHT@
package Socialtext::Search::Utils;
use strict;
use warnings;

use Readonly;

Readonly my $HARDENER => '000';

# Take "input" and return "input000", which is a hokey way of making sure a
# word doesn't get stemmed in the index, but is still somewhat readable for
# debugging purposes.
sub harden {
    my $input = shift;
    return $input . $HARDENER;
}

sub soften {
    my $input = shift;
    $input or return;
    $input =~ s/$HARDENER$//;
    return $input;
}

1;
