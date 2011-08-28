package Socialtext::Session;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

our $LAST_WORKSPACE_ID = undef;

sub last_workspace_id { $LAST_WORKSPACE_ID }

1;
