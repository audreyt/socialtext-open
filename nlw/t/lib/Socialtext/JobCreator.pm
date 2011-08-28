package Socialtext::JobCreator;
# @COPYRIGHT@

use strict;
use warnings;

our @to_index;

sub index_person {
    my $class = shift;
    my $maybe_user = shift;
    push @to_index, $maybe_user;

#    require Carp;
#    Carp::cluck "#\n#\n# index_person ($maybe_user)\n#\n#\n";
    warn "index_person ($maybe_user)";
}

1;
