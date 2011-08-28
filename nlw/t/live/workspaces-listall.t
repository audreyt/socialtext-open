#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live;
Test::Live->new->standard_query_validation;
__DATA__
=== workspaces_listall
# we expect five workspaces of known id but unknown name
--- query
action: workspaces_listall
--- match
<input type="hidden" name="selected_workspace_id" value="1" checked="checked" />
--- match
<input type="hidden" name="selected_workspace_id" value="2" checked="checked" />
--- match
<input type="hidden" name="selected_workspace_id" value="3" checked="checked" />
--- match
<input type="hidden" name="selected_workspace_id" value="4" checked="checked" />
--- match
<input type="hidden" name="selected_workspace_id" value="5" checked="checked" />

