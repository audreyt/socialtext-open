#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new()->standard_query_validation;
# XXX I hate the live tests, but need the live tests
# Ideally some of these would be doing dom checks, not string matches
__END__
=== Get the list categories page
--- request_path: /lite/category/admin
--- match
welcome

=== List pages in a category
--- request_path: /lite/category/admin/welcome
--- match
Quick Start
Start here
