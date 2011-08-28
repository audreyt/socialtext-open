#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
fixtures(qw( empty ));

filters {
    wiki => 'format',
};

my $hub = new_hub('empty');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== Check formatting of valid HTML fragment
--- wiki
.html
<b>some html</b>
.html
--- match
<div class="wiki">
<div class="wafl_block"><b>some html</b>
<!-- wiki:
.html
<b>some html</b>
.html
--></div>
</div>

=== Check formatting of screwy HTML fragment
--- wiki
.html
<p><b>some html</b>
.html
--- match
<div class="wiki">
<div class="wafl_block"><p><b>some html</b></p>
<!-- wiki:
.html
<p><b>some html</b>
.html
--></div>
</div>


