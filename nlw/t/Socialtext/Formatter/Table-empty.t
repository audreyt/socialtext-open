#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 5;
fixtures(qw( empty ));

filters {
    wiki => ['format'],
};

my $hub = new_hub('empty');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== simple table, no spaces
--- wiki
||||
||||
||||
--- match
<div class="wiki">
<table border="1" style="border-collapse:collapse" options="" class="formatter_table">
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
</table>
</div>

=== simple table, spaces
--- wiki
| | | |
| | | |
| | | |
--- match
<div class="wiki">
<table border="1" style="border-collapse:collapse" options="" class="formatter_table">
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
<tr>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
<td><span style="padding:.5em">&nbsp;</span></td>
</tr>
</table>
</div>

=== simple table, words
--- wiki
| foo | bar | baz |
| bar | baz | foo |
| baz | foo | bar |
--- match
<div class="wiki">
<table border="1" style="border-collapse:collapse" options="" class="formatter_table">
<tr>
<td>foo</td>
<td>bar</td>
<td>baz</td>
</tr>
<tr>
<td>bar</td>
<td>baz</td>
<td>foo</td>
</tr>
<tr>
<td>baz</td>
<td>foo</td>
<td>bar</td>
</tr>
</table>
</div>

=== simple table, words sortable
--- wiki
|| sortable
| foo | bar | baz |
| bar | baz | foo |
--- match
<div class="wiki">
<table border="1" style="border-collapse:collapse" options="sortable" class="formatter_table">
<tr>
<td>foo</td>
<td>bar</td>
<td>baz</td>
</tr>
<tr>
<td>bar</td>
<td>baz</td>
<td>foo</td>
</tr>
</table>
</div>

=== simple table, words borderless
--- wiki
|| border:off
| foo | bar | baz |
| bar | baz | foo |
--- match
<div class="wiki">
<table  style="border-collapse:collapse" options="border:off" class="formatter_table borderless">
<tr>
<td>foo</td>
<td>bar</td>
<td>baz</td>
</tr>
<tr>
<td>bar</td>
<td>baz</td>
<td>foo</td>
</tr>
</table>
</div>
