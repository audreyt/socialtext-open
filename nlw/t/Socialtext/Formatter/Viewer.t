#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
use Socialtext::Formatter::Viewer;

run_is;

BEGIN {
    use_ok( 'Socialtext::Formatter::Viewer' );
}

sub detab { Socialtext::Formatter::Viewer->_detab($_) }

__DATA__
=== A tsv table with actual hard tabs
--- tsv_table detab
tsv:
	<b>Considers	<b>Commits	<b>Reconsiders	<b>Unconsiders	<b>Stores	<b> Retrieve LT Memory	<b> Command Motor Action	<b>Test Committed Memory	<b>Test Consideration Memory	<b>Special
<b>Transforms	Any memory object	A memory object associated with a goal considered by a preference	Any memory object	A memory object associated with a goal considered by a preference	None	Any lt memory obje

--- expected
||<b>Considers|<b>Commits|<b>Reconsiders|<b>Unconsiders|<b>Stores|<b> Retrieve LT Memory|<b> Command Motor Action|<b>Test Committed Memory|<b>Test Consideration Memory|<b>Special|
|<b>Transforms|Any memory object|A memory object associated with a goal considered by a preference|Any memory object|A memory object associated with a goal considered by a preference|None|Any lt memory obje|

=== A tsv table with spaces
--- tsv_table detab
tsv:
    <b>Considers    <b>Commits    <b>Reconsiders    <b>Unconsiders    <b>Stores    <b> Retrieve LT Memory    <b> Command Motor Action    <b>Test Committed Memory    <b>Test Consideration Memory    <b>Special
<b>Transforms    Any memory object    A memory object associated with a goal considered by a preference    Any memory object    A memory object associated with a goal considered by a preference    None    Any lt memory obje

--- expected
||<b>Considers|<b>Commits|<b>Reconsiders|<b>Unconsiders|<b>Stores|<b> Retrieve LT Memory|<b> Command Motor Action|<b>Test Committed Memory|<b>Test Consideration Memory|<b>Special|
|<b>Transforms|Any memory object|A memory object associated with a goal considered by a preference|Any memory object|A memory object associated with a goal considered by a preference|None|Any lt memory obje|
