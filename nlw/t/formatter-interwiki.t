#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
fixtures( 'admin', 'foobar', 'public' );

filters {
    wiki => 'format',
    match => 'wrap_html',
};

my $hub = new_hub('admin');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

# XXX  Not sure about this result, however it looks fine in
# a browser
sub wrap_html {
    <<"...";
<div class="wiki">
$_<br /></div>
...
}

# XXX this test needs a skip or todo, but I couldn't get SKIP or TODO
# as advertised by Test::Base to do its thing?
#=== Interwiki link to public
## links to public are not currently working, see Socialtext::Users::in_workspace
#--- SKIP
#--- wiki
#{link: public [wiki 101]}
#--- match: <span class="nlw_phrase"><a title="inter-workspace link: public" href="/public/wiki_101">wiki 101</a><!-- wiki: {link: public [wiki 101]} --></span>
#

__DATA__
=== Interwiki link, with permission
--- wiki
{link: foobar [Quick Start]}
--- match: <span class="nlw_phrase"><a title="inter-workspace link: foobar" href="/foobar/quick_start">Quick Start</a><!-- wiki: {link: foobar [Quick Start]} --></span>

=== Interwiki link, without permission
--- wiki
{link: dev-tasks [Quick Start]}
--- match: <span class="nlw_phrase"><span class="wafl_permission_error">Quick Start</span><!-- wiki: {link: dev-=tasks [Quick Start]} --></span>

=== Interwiki link, with anchor
--- wiki
{link: foobar [Quick Start] anchor}
--- match: <span class="nlw_phrase"><a title="section link" href="/foobar/quick_start#anchor">Quick Start (anchor)</a><!-- wiki: {link: foobar [Quick Start] anchor} --></span>

