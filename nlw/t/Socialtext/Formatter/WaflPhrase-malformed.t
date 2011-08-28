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
=== labels on wafl phrases should not be greedy with ^ sign
--- wiki
^Malformed Header

one
two
three

--- match
<div class="wiki">
<p>
^Malformed Header<br />
</p>
<p>
one<br />
two<br />
three</p>
</div>

=== Ensure equal treatment for non-^-signed lines
--- wiki
Not Header

one
two
three

--- match
<div class="wiki">
<p>
Not Header<br />
</p>
<p>
one<br />
two<br />
three</p>
</div>

