#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 34;
use Socialtext::SQL qw(sql_execute);

fixtures(qw( db ));

=head1 DESCRIPTION

Test that backlinks are correctly created and removed
as pages are created and deleted.

=cut

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;
my $hub       = create_test_hub();
my $backlinks = $hub->backlinks;
my $pages     = $hub->pages;
my $workspace = $hub->current_workspace;

# check the preference that allows backlinks to be shown
my $user = Socialtext::User->create(
    username      => 'john@doe.com',
    email_address => 'john@doe.com',
    password      => 'whatever',
);
$hub->current_user($user);

my $page_one = Socialtext::Page->new(hub => $hub)->create(
    title => 'page one',
    content => "Hello\n{fake-wafl} this is page one to [page two]\nyou" .
               "\n\n{other fake-wafl} Hello [mr chips] and [the son] " .
               "how are\n" .
               "{include [page three]}\n\n" .
               "{include foobar [page three]}\n\n",

    creator => $user,
);

my $page_two = Socialtext::Page->new(hub => $hub)->create(
    title => 'page two',
    content => "Hello\nthis is page two to [page one]\nyou\n\nGoobye " .
               "[$singapore]\n",
    creator => $user,
);

my $page_three = Socialtext::Page->new(hub => $hub)->create(
    title => 'page three',
    content => "Hello\nthis is page three\n\nGoobye ",
    creator => $user,
);

my $page_four = Socialtext::Page->new(hub => $hub)->create(
    title => 'page four',
    content => "Hello\nthis is page links to [page five]\n",
    creator => $user,
);

my $page_five = Socialtext::Page->new(hub => $hub)->create(
    title => 'page five',
    content => qq!Hello\nthis page links to "super page"[page four]\n! .
    "{link: newworkspace [page four]}"
    ,
    creator => $user,
);

my $page_six = Socialtext::Page->new(hub => $hub)->create(
    title => 'page six',
    content => "Hello\nthis page links to page five [page five]\n",
    creator => $user,
);

my $page_seven = Socialtext::Page->new(hub => $hub)->create(
    title => 'page seven',
    content => "Hello\nthis page links to page five {link: [page five]}\n",
    creator => $user,
);

my $page_eight = Socialtext::Page->new(hub => $hub)->create(
    title => 'page eight',
    content => "Hello\nthis page links to page five {link: [page five] foosection}\n",
    creator => $user,
);

my $page_nine = Socialtext::Page->new(hub => $hub)->create(
    title => 'page nine',
    content => "Hello\nthis page links to some other workspace {link: other [page five] foosection}\n",
    creator => $user,
);

my $page_ten = Socialtext::Page->new(hub => $hub)->create(
    title => 'page ten',
    content => "Hello\nthis page links to this workspace {link: ".$workspace->name ." [page five] }\n",
    creator => $user,
);

# Test all_backlink_pages_for_page
{
    my @links = $backlinks->all_backlink_pages_for_page($page_one);
    is scalar(@links), 1, 'page one should only have one page that links to it';
    @links = $backlinks->all_backlink_pages_for_page($page_two);
    is scalar(@links), 1, 'page two should only have one page that links to it';
    @links = $backlinks->all_backlink_pages_for_page($page_four);
    is scalar(@links), 1, 'page four should have two pages that links to it';;
    @links = $backlinks->all_backlink_pages_for_page($page_five);
    is scalar(@links), 5, 'page five should have five pages that links to it';
}

TEST_FRONTLINK_PAGES: {
    check_frontlinks(
        $page_one, ['page three', 'page two'], ['mr_chips', 'the_son']
    );
    check_frontlinks($page_two, ['page one']);
    check_frontlinks($page_three, []);
    check_frontlinks($page_four, ['page five']);
    check_frontlinks($page_five, ['page four']);
    check_frontlinks($page_six, ['page five']);
    check_frontlinks($page_seven, ['page five']);
    check_frontlinks($page_eight, ['page five']);
    check_frontlinks($page_nine, []);
    check_frontlinks($page_ten, ['page five']);
}

{
    # this should be four: three freelinks and one local inclusion.
    # but not include foobar inclusion
    check_backlinks($page_one, $page_two, 4);
    check_backlinks($page_two, $page_one, 2);
    check_backlinks($pages->new_from_name($singapore), $page_two, 0);
    check_backlinks($pages->new_from_name('page three'), $page_one, 0);

    check_backlinks($page_six, undef, 1);
    check_backlinks($page_seven, undef, 1);
    check_backlinks($page_eight, undef, 1);
    check_backlinks($page_nine, undef, 0);
    check_backlinks($page_ten, undef, 1);

    $page_two->delete( user => $user );
    check_backlinks($page_two, undef, 0);

    $page_one->delete( user => $user );
    check_backlinks($page_one, undef, 0);
}

# from, to, count of links from from
sub check_backlinks {
    my $page = shift;
    my $top_backlink = shift;
    my $count = shift;

    my $links = $backlinks->all_backlinks_for_page($page);

    if ($top_backlink) {
        is($links->[0]{page_uri}, $top_backlink->uri, 'correct top link');
        is($links->[0]{page_title}, $top_backlink->title,
            'correct title in link');
    }

    my $sth = sql_execute('
        SELECT * FROM page_link
         WHERE from_workspace_id = ?
           AND from_page_id = ?
           AND from_workspace_id = to_workspace_id -- no interworkspace links
    ', $hub->current_workspace->workspace_id, $page->id);
    is($sth->rows, $count, "expect $count links in the files");
}

sub check_frontlinks {
    my $page = shift;
    my $titles = shift;
    my $incipients = shift;
    local $Test::Builder::Level = $Test::Builder::Level+1;

    my @pages = sort { $a->title cmp $b->title }
        $backlinks->all_frontlink_pages_for_page($page);
    my $actual = [map {$_->title } @pages];
    is_deeply(
        $actual, $titles,
        $page->title . " has the right front links"
    );

    if ($incipients) {
        my @pages = sort { $a->id cmp $b->id }
            $backlinks->all_frontlink_pages_for_page($page, 1);
        is_deeply(
            [map {$_->id } @pages], $incipients,
            $page->title . " has the right incipient front links"
        );
    }

}

