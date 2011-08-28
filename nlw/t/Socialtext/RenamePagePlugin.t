#!perl
# @COPYRIGHT@

use strict;
use warnings;

use mocked 'Apache::Cookie';
use Test::Socialtext tests => 8;
fixtures(qw( empty ));

my $hub = new_hub('empty');

{
    my $plugin = $hub->rename_page;

    my $html = $plugin->rename_popup();
    ok ($html =~ /Rename/, 'Got us a rename box');
}

BAD_PAGE_TITLE: {
    my $class      = 'Socialtext::RenamePagePlugin';
    my @bad_titles = (
        "Untitled Page",
        "Untitled ///////////////// Page",
        "&&&& UNtiTleD ///////////////// PaGe",
        "&&&& UNtiTleD ///////////////// PaGe *#\$*@!#*@!#\$*",
        "Untitled_Page",
        "",
    );
    for my $page (@bad_titles) {
        ok(
            $class->_page_title_bad("Untitled Page"),
            "Invalid title: \"$page\""
        );
    }
    ok( !$class->_page_title_bad("Cows Are Good"), "OK page title" );
}
