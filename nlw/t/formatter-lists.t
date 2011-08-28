#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext tests => 3;
fixtures(qw( empty ));

filters { wiki => 'format' };

my $viewer = new_hub('empty')->viewer;
isa_ok( $viewer, 'Socialtext::Formatter::Viewer' );

run_is wiki => 'html';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== Empty bullet in a unordered list
--- wiki
* one
*
* three
--- html
<div class="wiki">
<ul>
<li>one</li>
<li>&nbsp;</li>
<li>three</li>
</ul>
</div>

=== Empty bullet in a ordered list
--- wiki
# one
#
# three
--- html
<div class="wiki">
<ol>
<li>one</li>
<li>&nbsp;</li>
<li>three</li>
</ol>
</div>
