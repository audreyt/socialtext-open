#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin_with_extra_pages'];
Test::Live->new->standard_query_validation;

# Note: to understand how these assumptions can be made, see
# Test::Socialtext::Environment::get_deterministic_date_for_page 

__END__
=== Recent
--- query
action: recent_changes
changes: recent
--- match
Changes in Last Week \(\d+\)
Internationalization
--- nomatch
magic:css

=== All
--- query
action: recent_changes
changes: all
--- match
All Pages \(\d+\)
Quick Start
