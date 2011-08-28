#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 6;
fixtures( 'admin_with_ordered_pages', 'foobar_with_ordered_pages' );

BEGIN {
    use_ok( "Socialtext::RecentChangesPlugin" );
}

my $workspace_hub = new_hub('admin');

run {
    my $case = shift;
    my $got = $workspace_hub->viewer->text_to_html($case->kwiki);
    smarter_like($got, $case->htmlre, $case->name);
};

__DATA__

=== {recent_changes}
--- kwiki
{recent_changes}
--- htmlre
action=recent_changes
admin page five
admin page four
admin page three
admin page two
admin page one

=== {recent_changes foobar}
--- kwiki
{recent_changes foobar}
--- htmlre
action=recent_changes
foobar page five
foobar page four
foobar page three
foobar page two
foobar page one

=== {recent_changes <foobar>}
--- kwiki
{recent_changes <foobar>}
--- htmlre
action=recent_changes
foobar page five
foobar page four
foobar page three
foobar page two
foobar page one

=== {recent-changes-full foobar}
--- kwiki
{recent-changes-full foobar}
--- htmlre
<!-- wiki: {recent_changes_full: foobar}
--></div><br /></div>

=== {recent-changes-full <foobar>}
--- kwiki
{recent-changes-full <foobar>}
--- htmlre
<!-- wiki: {recent_changes_full: <foobar>}
--></div><br /></div>


