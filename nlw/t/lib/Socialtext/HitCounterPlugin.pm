package Socialtext::HitCounterPlugin;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

our $COUNTER = 0;

sub hit_counter_increment { return ++$COUNTER }

sub get_page_counter_value { return $COUNTER }

1;
