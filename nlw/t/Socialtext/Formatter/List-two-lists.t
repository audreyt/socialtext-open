#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 1;
fixtures(qw( empty ));

filters {
    wiki => 'format',
    match => 'wrap_html',
};

my $hub = new_hub('empty');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

sub wrap_html {
    <<"...";
<div class="wiki">
$_</div>
...
}

__DATA__
=== Two lists should now have empty paragraph (<br>) preserved between.
--- wiki
* foo

* bar
--- match
<ul>
<li>foo</li>
</ul>
<br /><ul>
<li>bar</li>
</ul>
