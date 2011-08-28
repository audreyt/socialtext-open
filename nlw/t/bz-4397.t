#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 7;
fixtures(qw( empty ));

filters {
    wiki => 'format',
    match => 'wrap_html',
};

my $viewer = new_hub('empty')->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

sub wrap_html {
    chomp;
    <<"...";
<div class="wiki">
<p>
$_</p>
</div>
...
}

__DATA__
=== Normal linebreaks
--- wiki
line1
line2
--- match
line1<br />
line2

=== Phrase markup across lines should have no effect (asterisk)
--- wiki
*line1
line2*
--- match
*line1<br />
line2*

=== Phrase markup across lines should have no effect (underscore)
--- wiki
_line1
line2_
--- match
_line1<br />
line2_

=== Phrase markup across lines should have no effect (dash)
--- wiki
-line1
line2-
--- match
-line1<br />
line2-

=== Phrase markup across lines should have no effect (backtick)
--- wiki
`line1
line2`
--- match
`line1<br />
line2`

=== Phrase markup across lines should have no effect (double braces)
--- wiki
{{line1
line2}}
--- match
{{line1<br />
line2}}

=== Phrase markup across lines should have no effect (wafl)
--- wiki
{date:
2010-09-15 10:36:30 GMT}
--- match
{date:<br />
2010-09-15 10:36:30 GMT}
