#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => [ 'admin', 'foobar' ];
Test::Live->new->standard_query_validation;
__DATA__
=== Central page
--- query
page_name: admin wiki
--- match
This is the home page for Admin Wiki.

=== Copy-to-workspace form (which is a pop-up in the UI)
--- query
action: copy_to_workspace_popup
page_name: admin wiki
--- match
Copy the page <[^>]+>"Admin Wiki"</[^>]+> to another workspace\?

=== Do it
--- post
target_workspace_id: Foobar Wiki (foobar)
--- match
body onload="window.close

=== Check the destination space
--- request_path: /foobar/index.cgi?Admin%20Wiki
--- match
This is the home page for Admin Wiki.

=== Get the popup again
--- query
action: copy_to_workspace_popup
page_name: admin wiki
--- match
Copy the page <[^>]+>"Admin Wiki"</[^>]+> to another workspace\?

=== Do it with empty name
--- post
target_workspace_id: Foobar Wiki (foobar)
new_title:
--- match
Please enter or change the page name.

=== Get the popup again
--- query
action: copy_to_workspace_popup
page_name: admin wiki
--- match
Copy the page <[^>]+>"Admin Wiki"</[^>]+> to another workspace\?

=== Copy page with duplicate name
--- post
target_workspace_id: Foobar Wiki (foobar)
new_title: foobar wiki
--- match
already in use in workspace

=== Get the duplicate popup
--- query
action: duplicate_popup
page_name: admin wiki
--- match
Duplicate 'Admin Wiki'

=== Make sure duplicate popup has category and attachment checked
--- query
action: duplicate_popup
page_name: admin wiki
--- match
<input .*name="keep_categories".*checked="true" />

=== Duplicate it correctly
--- post
new_title: cherry blossoms
--- match
body onload="window.opener.location='index.cgi\?cherry_blossoms'

=== Get the duplicate popup again
--- query
action: duplicate_popup
page_name: admin wiki
--- match
Duplicate 'Admin Wiki'

=== Duplicate to nothing
--- post
new_title:
--- match
Please enter or change the page name.

=== Get the duplicate popup again
--- query
action: duplicate_popup
page_name: admin wiki
--- match
Duplicate 'Admin Wiki'

=== Duplicate to existing page
--- post
new_title: cherry blossoms
--- match
The new page name .+ is already in use.

=== Get the duplicate popup again
--- query
action: duplicate_popup
page_name: admin wiki
--- match
Duplicate 'Admin Wiki'

=== Remove edit permission for workspace admin
--- do: removePermission workspace_admin edit

=== Duplicate to existing page without edit permission, should close window
--- post
new_title: Some Random Title Which Should Not Exist Yet
--- match
window.close

=== Make sure new page does not exist
--- request_path: /admin/index.cgi?some_random_title_which_should_not_exist_yet
--- nomatch
This is the home page for Admin Wiki
