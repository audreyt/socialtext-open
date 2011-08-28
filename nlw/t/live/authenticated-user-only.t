#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin', 'foobar'];
Test::Live->new(dont_log_in => 1)->standard_query_validation;
__END__
=== Log in as devnull2
--- do: log_in devnull2@socialtext.com d3vnu11l

=== Verify that you can view the foobar workspace
--- request_path: /foobar/index.cgi?Quick_Start
--- match
type as you like

=== Verify that you CAN'T view the admin workspace
--- request_path: /admin/index.cgi?Quick_Start
--- match
action="/nlw/submit/login"

=== Set perms to authenticated-user-only
--- do: setPermissions set_name authenticated-user-only

=== Verify that you CAN now view the admin workspace
--- request_path: /admin/index.cgi?Quick_Start
--- match
type as you like
