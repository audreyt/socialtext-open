#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];

Test::Live->new()->standard_query_validation;

__DATA__
=== empty page id 
--- query
action: page_stats_index
page_id: 
--- match
No page ID

=== no page_id sent
--- query
action: page_stats_index
--- match
No page ID

=== invalid page id given 
--- query
action: page_stats_index
page_id: zzzzzzzz9999999999
--- match
invalid page ID
