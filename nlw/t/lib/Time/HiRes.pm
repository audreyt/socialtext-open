package Time::HiRes;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw/time sleep/;

our $TIME = 1;

sub time { return $TIME++ }
sub sleep { sleep $_[0] }

1;
