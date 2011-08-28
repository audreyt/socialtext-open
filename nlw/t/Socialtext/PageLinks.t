#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 20;
use Test::Socialtext;
use File::Path qw(mkpath);
use Socialtext::SQL qw(sql_execute);

fixtures('db');
use_ok 'Socialtext::PageLinks';

my $hub = create_test_hub;

# SETUP:
my $page1 = Socialtext::Page->new( hub => $hub )->create(
    title      => 'Page 1',
    content    => 'Some content',
    date       => DateTime->new( year => 2000, month => 2, day => 1 ),
    creator    => $hub->current_user,
);
my $page2 = Socialtext::Page->new( hub => $hub )->create(
    title      => 'Page 2',
    content    => 'a link to [Page 1]',
    date       => DateTime->new( year => 2000, month => 2, day => 1 ),
    creator    => $hub->current_user,
);
my $page3 = Socialtext::Page->new( hub => $hub )->create(
    title      => 'Page 3',
    content    => 'a link to [Page 1] and [incipient]',
    date       => DateTime->new( year => 2000, month => 2, day => 1 ),
    creator    => $hub->current_user,
);
my $page4 = Socialtext::Page->new( hub => $hub )->create(
    title      => 'Page 4',
    content    => 'Hi there [page 3]',
    date       => DateTime->new( year => 2000, month => 2, day => 1 ),
    creator    => $hub->current_user,
);

my $links1 = Socialtext::PageLinks->new(page => $page1, hub => $hub);
my $links2 = Socialtext::PageLinks->new(page => $page2, hub => $hub);
my $links3 = Socialtext::PageLinks->new(page => $page3, hub => $hub);

is $page1->content, "Some content\n", "setup page1 properly";

Forward_links: {
    is @{$links1->links}, 0, "page 1 has no forward link";

    is @{$links2->links}, 1, "page 2 has one forward link";
    is $links2->links->[0]->id, $page1->id, "... with page id";
    is $links2->links->[0]->content, $page1->content, "... with content";

    is @{$links3->links}, 2, "page 3 has two forward link";
    is $links3->links->[0]->active, 0, "... second is incipient";
    is $links3->links->[1]->id, $page1->id, "... first has page id";
    is $links3->links->[1]->content, $page1->content, "... first has content";
    is $links3->links->[1]->active, 1, "... first is not incipient";
}

Back_Links: {
    is @{$links1->backlinks}, 2, "page 1 has two backlinks";
    is $links1->backlinks->[0]->id, $page2->id, "... with page id";
    is $links1->backlinks->[0]->content, $page2->content, "... with content";
    is $links1->backlinks->[1]->id, $page3->id, "... with page id";
    is $links1->backlinks->[1]->content, $page3->content, "... with content";

    is @{$links2->backlinks}, 0, "page 2 has no backlinks";

    is @{$links3->backlinks}, 1, "page 3 has one backlink";
    is $links3->backlinks->[0]->id, $page4->id, "... with page id";
    is $links3->backlinks->[0]->content, $page4->content, "... with content";
}
