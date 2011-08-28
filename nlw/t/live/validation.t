#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new->standard_query_validation;
__DATA__
=== edit_save with missing params
--- query
action: edit_save
--- MATCH_WHOLE_PAGE
--- match
Malformed query.+Please send email to.*if you think it should have worked\.

=== attachments_upload with missing params
--- query
action: attachments_upload
--- MATCH_WHOLE_PAGE
--- match
The file you are trying to upload does not exist

=== Unknown action
--- query
action: i_like_cows_please_do_not_eat_them
--- MATCH_WHOLE_PAGE
--- match
An invalid action, i_like_cows_please_do_not_eat_them, was entered\. Returning to front page\.
