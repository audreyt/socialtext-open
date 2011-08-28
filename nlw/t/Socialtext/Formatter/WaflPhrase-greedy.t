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
=== labels on wafl phrases should not be greedy
--- wiki
"Hello Everyone" said the "monkey"{link: ape}
--- match
<div class="wiki">
<p>
&quot;Hello Everyone&quot; said the <span class="nlw_phrase"><a title="section link" href="#ape">monkey</a><!-- wiki: "monkey"{link: ape} --></span></p>
</div>

=== labels on wafl phrases should not conflict with other labels
--- wiki
"Click me"<http://www.example.com> and "win"{link: ape}
--- match
<div class="wiki">
<p>
<a target="_blank" rel="nofollow" title="(external link)" href="http://www.example.com">Click me</a> and <span class="nlw_phrase"><a title="section link" href="#ape">win</a><!-- wiki: "win"{link: ape} --></span></p>
</div>
