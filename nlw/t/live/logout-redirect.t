#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['workspaces'];

my $tester = Test::Live->new;
$tester->dont_log_in(1);
$tester->standard_query_validation;

__DATA__
=== Attempt to access a page that requires login
--- query
page_name: welcome
action: display
--- match: Log in to Socialtext

=== Log in, which should contain empty logout
--- MATCH_WHOLE_PAGE
--- post
username: devnull1@socialtext.com
password: d3vnu11l
--- match
"/nlw/submit/logout"

=== Go to other workspace, should contain redirect logout
--- MATCH_WHOLE_PAGE
--- request_path: /auth-to-edit/index.cgi
--- match
"/nlw/submit/logout\?redirect_to=.+"
