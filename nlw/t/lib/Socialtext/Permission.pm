package Socialtext::Permission;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use base 'Exporter';

our @EXPORT_OK = qw/ST_READ_PERM ST_ADMIN_WORKSPACE_PERM ST_EDIT_PERM/;

sub ST_READ_PERM { 1 }
sub ST_ADMIN_WORKSPACE_PERM { 1 }
sub ST_EDIT_PERM { 1 }
1;
