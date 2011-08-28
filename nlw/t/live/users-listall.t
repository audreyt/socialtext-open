#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live;
Test::Live->new->standard_query_validation;
__DATA__
=== users_listall
# we expect one user in this workspace
--- query
action: users_listall
--- match
devnull1@socialtext.com
--- match
name="should_be_admin" checked="checked"
