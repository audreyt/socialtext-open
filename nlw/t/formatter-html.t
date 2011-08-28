#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 1;

fixtures(qw( empty ));

###############################################################################
# TEST: HTML wafl blocks
html_wafl_blocks: {
    my $wikitext = ".html\n<div>one\n.html\n";
    my $expected = qr[
        <div\s+class="wafl_block"><div>one\s+</div>\n
        <!--\s+wiki:\n
        .html\n
        <div>one\n
        .html\n
        --></div>
        ]x;
    formatted_like $wikitext, $expected;
}
