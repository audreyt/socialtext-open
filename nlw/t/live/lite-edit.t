#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new()->standard_query_validation;
# XXX I hate the live tests, but need the live tests
# Ideally some of these would be doing dom checks, not string matches
__END__
=== Hit a non-existent page
--- request_path: /lite/page/admin/Test%20Page%20One?action=edit
--- match
method="post"
action="/lite/page/admin/Test%20Page%20One"

=== Make an edit
--- form: editform
--- post
page_body: The content of test page one
--- match
        <div class="wiki">
<p>
The content of test page one</p>
</div>

=== Check for the page in changes
--- request_path: /lite/changes/admin
--- match
        <ul>
            <li>
                <a title="Test Page One"
                   href="/lite/page/admin/test_page_one">Test Page One</a>
            </li>

=== Fetch the edit form
--- request_path: /lite/page/admin/Test%20Page%20One?action=edit
--- match
method="post"
action="/lite/page/admin/test_page_one

=== Remove edit permission for workspace admin
--- do: removePermission workspace_admin edit

=== Make an edit without edit permission
--- form: editform
--- post
page_body: A brand new body!
--- nomatch
A brand new body

=== Fetch the edit form again
--- request_path: /lite/page/admin/Test%20Page%20One?action=edit
--- nomatch
method="post"
action="/lite/page/admin/test_page_one

=== Fetch the page
--- request_path: /lite/page/admin/Test%20Page%20One
--- nomatch
action=edit

