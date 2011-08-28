package Socialtext::Authz;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';

sub user_has_permission_for_workspace { 1 }
sub plugin_enabled_for_user { 1 }
sub plugin_enabled_for_users { 1 }

1;
