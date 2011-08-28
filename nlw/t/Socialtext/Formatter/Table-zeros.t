#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 1;
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
=== simple table
--- wiki
| 0 | 1 | 1 |
| 1 | 0 | 1 |
| 1 | 1 | 0 |
--- match
<div class="wiki">
<table border="1" style="border-collapse:collapse" options="" class="formatter_table">
<tr>
<td>0</td>
<td>1</td>
<td>1</td>
</tr>
<tr>
<td>1</td>
<td>0</td>
<td>1</td>
</tr>
<tr>
<td>1</td>
<td>1</td>
<td>0</td>
</tr>
</table>
</div>
