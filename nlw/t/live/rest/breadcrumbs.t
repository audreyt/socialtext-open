#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::HTTP::Socialtext '-syntax', tests => 4;

use Readonly;
use Test::Live fixtures => ['admin_no_pages'];
use Test::More;
use Test::Socialtext::Environment;
use mocked 'Apache::Cookie';

Readonly my $CRUMBS =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/breadcrumbs');
Readonly my $PAGES =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $PAGE_ONE => 'page one';
Readonly my $PAGE_TWO => 'page two';

Readonly my $NEW_BODY      => "You got to drop her like a trig class.\n";

# put some pages
test_http "PUT new page one" {
    my $body = $NEW_BODY . "\n\n[page two]";

    >> PUT $PAGES/$PAGE_ONE
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $body

    << 201

}

test_http "PUT new page two" {
    my $body = $NEW_BODY . "\n\n[page one]";

    >> PUT $PAGES/$PAGE_TWO
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $body

    << 201
}

# visit them
my $hub = Test::Socialtext::Environment->instance()->hub_for_workspace('admin');
$hub->pages->current($hub->pages->new_from_name('page one'));
$hub->display->display;
$hub->pages->current($hub->pages->new_from_name('page two'));
$hub->display->display;

test_http "GET page one breadcrumbs" {
    >> GET $CRUMBS
    >> Accept: text/plain

    << 200

    my $content = $test->response->content;
    is $content, "page two\npage one\n", "content is correct";

}

