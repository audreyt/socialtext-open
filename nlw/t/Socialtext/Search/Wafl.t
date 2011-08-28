#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 7;

fixtures(qw(clean admin_with_ordered_pages foobar_with_ordered_pages));

BEGIN {
    use_ok( "Socialtext::SearchPlugin" );
}

my $workspace_hub = new_hub('admin');

Test::Socialtext::ceqlotron_run_synchronously();

my $order_doesnt_matter = 1;
run {
    my $case = shift;
    my $got = $workspace_hub->viewer->text_to_html($case->kwiki);
    smarter_like($got, $case->htmlre, $case->name, $order_doesnt_matter);
};

__DATA__

=== {search title:page}
--- kwiki
{search title:page}
--- htmlre
action=search;search_term=title%3Apage
admin page six
admin page five
admin page four
admin page three
admin page two
admin page one

=== {search <foobar> title:page}
--- kwiki
{search <foobar> title:page}
--- htmlre
foobar/\?action=search;search_term=title%3Apage
foobar page six
foobar page five
foobar page four
foobar page three
foobar page two
foobar page one

=== {search-full title:admin}
--- kwiki
{search-full title:admin}
--- htmlre
<!-- wiki: {search_full: title:admin}
--></div><br /></div>

=== {search title:page workspaces:admin,foobar}
--- kwiki
{search title:page workspaces:admin,foobar}
--- htmlre
action=search;search_term=title%3Apage%20workspaces%3Aadmin%2Cfoobar
foobar page six
admin page six
foobar page five
admin page five
foobar page four
admin page four
foobar page three
admin page three
foobar page two
admin page two
foobar page one
admin page one

=== {search-full title:admin workspaces:admin,foobar}
--- kwiki
{search-full title:page workspaces:admin,foobar}
--- htmlre
<!-- wiki: {search_full: title:page workspaces:admin,foobar}
--></div><br /></div>

