#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];

Test::Live->new()->standard_query_validation;

__DATA__
=== no page name selected
--- query
action: rtf_export
page_selected: 
--- match
No page name

=== no page_selected sent
--- query
action: rtf_export
--- match
No pages selected

=== invalid page name selected
--- query
action: rtf_export
page_selected: zzzzzzzz9999999999
--- match
invalid page name
