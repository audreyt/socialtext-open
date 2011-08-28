#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 6;
use Socialtext::Encode;
use IO::File;

fixtures('clean','db');
my $hub = create_test_hub();
my $user = $hub->current_user;
my $ws_name = $hub->current_workspace->name;

{
    my $name = "Formatter Test for html-page wafl";
    my $page = $hub->pages->new_from_name($name);
    $page->content('foo'); # run_tests will replace it later
    $page->store();

    my $attachment = $hub->attachments->create(
        fh => IO::File->new('t/attachments/html-page-wafl.html','r'),
        page_id => $page->id,
        filename => 'html-page-wafl.html',
        user => $hub->current_user,
    );

    my @tests =
        ( [ "{html-page html-page-wafl.html}\n" =>
            qr{href="/data/workspaces/$ws_name/attachments/formatter_test_for_html_page_wafl:\S+?/html-page-wafl.html},
            qr{\Qhtml-page-wafl.html;as_page=1\E},
          ],
          [ "{html-page no-such-page.html}\n" =>
            qr{\Qno-such-page.html\E},
            qr{(?!href)},
          ],
        );

    run_tests( $page, $_ ) for @tests;
}

{
    my $page = $hub->pages->new_from_name('Another html-page wafl test page');
    $page->content('foo');
    $page->store();

    my @tests =
        ( [ "{html-page [Formatter Test for html-page wafl] html-page-wafl.html}\n" =>
            qr{href="/data/workspaces/$ws_name/attachments/formatter_test_for_html_page_wafl:\S+?/html-page-wafl.html},
            qr{\Qhtml-page-wafl.html;as_page=1\E},
          ],
        );

    run_tests( $page, $_ ) for @tests;
}

sub run_tests {
    my ($page, $tests) = @_;

    # XXX without this the existence of the attachment to the page
    # is not correct, and the test fails, so there appears to be
    # an issue with a hidden dependency on current
    $page->hub->pages->current($page);

    my $text = shift @$tests;
    $page->edit_rev();
    $page->content($text);
    $page->store();

    my $html = $page->to_html;

    for my $re (@$tests) {
        my $name = $text;
        chomp $name;

        $name .= " =~ $re";

        like( $html, $re, $name );
    }
}
