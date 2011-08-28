#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin_with_extra_pages'];
Test::Live->new()->standard_query_validation;
__END__
=== Hit a page
--- query
page_name: Babel
action: display
--- match
confundir

=== Delete it, and make sure you're redirected to an epilogue page
--- query
page_name: Babel
action: delete_page
--- match
Did you delete this page in error\? If so, you can restore the page.
<form method="post" action="index.cgi">
<input type="hidden" name="action" value="undelete_page" />
<input type="hidden" name="page_id" value="babel" />

=== Look at its History
--- query
page_name: babel
action: revision_list
--- XXX: note the weirdness where it has two "revision 1"s.  See rt#13098
--- match
Babel:[^\n]*All Revisions
revision&nbsp;1
revision&nbsp;1

=== Hit another page
--- query
page_name: Quick Start
action: display
--- match
Here's the 2-minute basic intro

=== Remove delete permission for workspace admin
--- do: removePermission workspace_admin delete

=== Delete it, without delete permission, and redirects to display
--- query
page_name: Quick Start
action: delete_page
--- match
Here's the 2-minute basic intro

