#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new->standard_query_validation;

__DATA__
=== Get comment popup
--- query
action: enter_comment
page_name: admin_wiki
--- match
Add Comment

=== Submit Comment
--- post
action: submit_comment
page_name: admin_wiki
comment: A thoughtful comment
--- match
window.close

=== Get Central Page
--- request_path: /admin/index.cgi?admin_wiki
--- match
A thoughtful comment

=== Get comment popup
--- query
action: enter_comment
page_name: admin_wiki
--- match
Add Comment

=== Remove comment permission for workspace admin
--- do: removePermission workspace_admin comment

=== Submit Comment without comment permission
--- post
action: submit_comment
page_name: admin_wiki
comment: A stupid comment
--- match
window.close

=== Get Central Page
--- request_path: /admin/index.cgi?admin_wiki
--- nomatch
A stupid comment
