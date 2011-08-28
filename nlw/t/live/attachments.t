#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new()->standard_query_validation;
__DATA__
=== Get main page
--- request_path: /admin/index.cgi?admin_wiki
--- match: home page

=== Attach a file
--- form: attachForm
--- post
file: t/extra-attachments/live/attachments.t/test.txt
--- match: test\.txt

=== Make sure page has attachment
--- request_path: /data/workspaces/admin/pages/admin_wiki/attachments
--- match: test\.txt

=== Make sure attachment has correct data
--- follow_link
text: test.txt
n: 1
--- match_file: t/extra-attachments/live/attachments.t/test.txt

=== Back to the home page
--- request_path: /admin/index.cgi?admin_wiki
--- match: home page

=== Attach a binary file
--- form: attachForm
--- post
file: t/extra-attachments/live/attachments.t/thing.png

=== Make sure page has 2 attachment
--- request_path: /data/workspaces/admin/pages/admin_wiki/attachments
--- match
test\.txt
thing\.png
