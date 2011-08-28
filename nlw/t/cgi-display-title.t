#!perl
# @COPYRIGHT@

use strict;
use warnings;

use mocked 'Apache::Cookie';
use Test::Socialtext tests => 10;
fixtures( 'admin' );
use Test::Socialtext::CGIOutput;

# existing uri to title
perform_query('quick_start', 'Quick Start');

# existing name to title
perform_query('Quick%20Start', 'Quick Start');

# non-existing name to title
perform_query('who is zippy frobnitz', 'who is zippy frobnitz');

# non-existing name to title
perform_query('Who%20is%20Zippy%20Frobnitz', 'Who is Zippy Frobnitz');

# triple digit % name to title
perform_query('Edit%20in%20place%20phase%200', 'Edit in place phase 0');

sub perform_query {
    my $name = shift;
    my $title = shift;

    test_init();
    set_query("action=display;page_name=$name");

    my $hub = new_hub('admin');
    my ($error, $html) = get_action_output(
        $hub, 'display', 'display');

    is($error, '', 'page load succeeds');
    like($html, qr/page-titletext"[^>]*>\s*$title\s*<\//sm,
        'proper title for page');
}
