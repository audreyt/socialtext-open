package Socialtext::Schema;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

our $CURRENT_VERSION = 1;

sub current_version { $CURRENT_VERSION }

sub sync {
    my $self = shift;
    my %p    = @_;

    if ($p{to_version}) {
        $CURRENT_VERSION = $p{to_version};
    }
}

1;
