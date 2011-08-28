#!perl
# @COPYRIGHT@
use strict;
use warnings;

use DateTime;
use mocked 'Socialtext::Events';
use Test::Socialtext tests => 59;
use Test::Socialtext::Fatal;
use Test::Deep;
use ok 'Socialtext::Page';

fixtures(qw( db ));

URI: {
    my $hub = create_test_hub();
    my $page = $hub->pages->new_from_name("Some Page / Test");
    ok $page->mutable, "page doesn't exist";
    is $page->page_id, "some_page_test", "id";
    is $page->uri, "Some%20Page%20%2F%20Test", "incipient uri (never existed)";
    $page->store();
    is $page->uri, "some_page_test", "exists-uri";
    
    #double check on reload
    $page = $hub->pages->new_from_name("Some Page     Test");
    is $page->uri, "some_page_test", "exists-uri";
}

NEWLINE: {
    my $hub = create_test_hub();
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title   => 'new page',
        content => 'First Paragraph',
        creator => $hub->current_user,
    );
    is $page->content, "First Paragraph\n", "newline got added";
}

APPEND: {
    my $hub = create_test_hub();
    my $page = Socialtext::Page->new(hub => $hub)->create(
        title   => 'new page',
        content => 'First Paragraph',
        creator => $hub->current_user,
    );
    is $page->content, "First Paragraph\n", 'initial content';
    is $page->content, "First Paragraph\n", 'initial content';
    ok $page->is_recently_modified(), 'page is recently modified';
    ok !$page->mutable;

    like exception {
        $page->append("Shouldn't append");
    }, qr/page isn't mutable/, "can't append until page is open for edit";

    $page->edit_rev(editor => $hub->current_user);
    $page->append('Second Paragraph');
    is $page->content, "First Paragraph\n\n---\nSecond Paragraph",
        'appended';
}

PREPEND: {
    my $hub  = create_test_hub();
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'new page',
        content => 'First Paragraph',
        creator => $hub->current_user,
    );
    is $page->content, "First Paragraph\n", 'initial content';
    ok $page->is_recently_modified(), 'page is recently modified';
    ok !$page->mutable;

    like exception {
        $page->prepend("Shouldn't prepend");
    }, qr/page isn't mutable/, "can't prepend until page is open for edit";

    $page->edit_rev(editor => $hub->current_user);
    $page->prepend('Second Paragraph');
    is $page->content, "Second Paragraph\n---\nFirst Paragraph\n",
        'prepended';
}

RENAME: {
    my $hub   = create_test_hub();

    my $page1 = Socialtext::Page->new( hub => $hub )->create(
        title   => 'My First Page',
        content => 'First Paragraph',
        creator => $hub->current_user,
    );
    my $page2 = Socialtext::Page->new( hub => $hub )->create(
        title   => 'My Second Page',
        content => 'Another paragraph first',
        creator => $hub->current_user,
    );

    my $return;
    is exception {
        $return = $page1->rename('My Second Page');
    }, undef, "no exception";
    is $return, 0, "Can't accidentally clobber";

    is exception {
        $return = $page1->rename('My Renamed Page');
    }, undef, "no exception";
    is $return, 1, 'Rename to another page should return ok';
    is $page1->content, "Page renamed to [My Renamed Page]\n",
        'Original page content should point to new page';
}

RENAME_CLOBBER: {
    my $hub   = create_test_hub();
    my $page1 = Socialtext::Page->new( hub => $hub )->create(
        title   => 'My First Page',
        content => 'First Paragraph',
    );
    my $page2 = Socialtext::Page->new( hub => $hub )->create(
        title   => 'My Second Page',
        content => 'Another paragraph first',
    );

    my $return;
    is exception {
        $return = $page1->rename('My Second Page', 1, 1, 'My Second Page');
    }, undef, "no exception";
    is $return, 1, 'Return should be ok as existing page should be clobbered';
    is $page1->content, "Page renamed to [My Second Page]\n",
        'Original page content should point to new page';

    $page2 = $hub->pages->new_from_name('My Second Page');
    is $page2->content, "First Paragraph\n",
        'Exising page should have content of new page';
}

RENAME_WITH_OVERLAPPING_IDS: {
    my $hub  = create_test_hub();
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'I LOVE COWS SO MUCH I COULD SCREAM',
        content => 'COWS LOVE ME',
    );
    my $old_id = $page->page_id;

    my $new_title = 'I Love Cows So Much I Could SCREAM!!!!!!!';
    my $return    = $page->rename($new_title);
    is $return, 1, 'Rename of a page where new name has same page_id';
    is $page->title,   $new_title, "title got changed";
    is $page->content, "COWS LOVE ME\n", "same content";
    is $page->page_id, $old_id, "same page id";
}

LOAD_WITH_REVISION: {
    my $hub  = create_test_hub();
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'revision_page',
        content => 'First Paragraph',
    );
    $page->edit_rev();
    $page->append('Second Paragraph');
    $page->store(user => $hub->current_user);

    my @ids = $page->all_revision_ids();
    is scalar(@ids), 2, 'Number of revisions';

    my $oldPage = Socialtext::Page->new( hub => $hub, id=>'revision_page' );
    $oldPage->load_revision($ids[0]);
    is $oldPage->content,"First Paragraph\n", 'Content matches first revision';

    $oldPage = Socialtext::Page->new( hub => $hub, id=>'revision_page' );
    $oldPage->load_revision($ids[1]);
    is $oldPage->content,"First Paragraph\n\n---\nSecond Paragraph\n",
        'Content matches latest revision';

    is $oldPage->content, $page->content, 'Content matches latest revision';
}

IS_RECENTLY_MODIFIED: {
    my $hub  = create_test_hub();
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'new page',
        content => 'new page',
        creator => $hub->current_user,
    );
    ok $page->is_recently_modified(), 'page is recently modified';

    my $four_hours_ago = Socialtext::Date->now(hires=>1)
        ->subtract(hours => 4);
    my $page2 = Socialtext::Page->new( hub => $hub )->create(
        title   => 'new page 2',
        content => 'new page 2',
        date    => $four_hours_ago,
        creator => $hub->current_user,
    );
    is $page2->create_time->epoch, $page2->last_edit_time->epoch,
        "create and edit dates are the same";
    cmp_ok $page->create_time, '>', $page2->create_time,
        'page created "before"';
    ok !$page2->is_recently_modified(), 'page is not recently modified';
    ok $page2->is_recently_modified(60 * 60 * 5),
        'page is recently modified compared to 5hrs ago';
}

NOW_WAFL_EXPANSION: {
    my $hub = create_test_hub();
    isa_ok $hub, 'Socialtext::Hub';

    # create a new page, and track the time before+after the creation
    my $t_before = DateTime->now;
    my $page = Socialtext::Page->new( hub => $hub )->create(
        title   => 'now wafl test',
        content => '{now}',
        creator => $hub->current_user,
    );
    isa_ok $page, 'Socialtext::Page';
    my $t_after = DateTime->now;

    # make sure that the "{now}" wafl got expanded out to a timestamp
    # somewhere between the before+after times
    unlike $page->content, qr/{now}/, "no raw wafl";
    my $formatter = DateTime::Format::Strptime->new( pattern => '%F %T %Z' );
    my $t_content = $formatter->parse_datetime( $page->content );
    isa_ok $t_content, 'DateTime', 'expanded+parsed {now} wafl';
    ok $t_content >= $t_before, '{now} was after start time';
    ok $t_content <= $t_after, '{now} was before end time';
}

MAX_ID_LENGTH: {
    my $hub  = create_test_hub();
    my $title = 'z' x 256;
    like exception {
        Socialtext::Page->new( hub => $hub )->create(
            title   => $title,
            content => 'foo',
        );
    }, qr/Page title is too long/, 'too long';

    # assumes the page id limit is 255
    $title = 'x' x 254;
    $title .= chr(22369); # the last character in Singapore
    like exception {
        Socialtext::Page->new( hub => $hub )->create(
            title   => $title,
            content => 'bar',
        );
    }, qr/Page title is too long/, 'too long with unicode';
}

BAD_PAGE_TITLE: {
    my $class      = 'Socialtext::Page';
    my @bad_titles = (
        "Untitled Page",
        "Untitled ///////////////// Page",
        "&&&& UNtiTleD ///////////////// PaGe",
        "&&&& UNtiTleD ///////////////// PaGe *#\$*@!#*@!#\$*",
        "Untitled_Page",
        "",
    );
    for my $title (@bad_titles) {
        my $isbad = Socialtext::Page->is_bad_page_title($title);
        ok $isbad, "Invalid title: \"$title\"";
    }
    ok !$class->is_bad_page_title("Cows Are Good"), "OK page title";
}

INVALID_UTF8: {
    my $hub = create_test_hub();
    like exception {
        my $page = Socialtext::Page->new( hub => $hub )->create(
            title   => 'new page',
            content => "* hello\n** \xdamn\n",
            creator => $hub->current_user,
        );
    }, qr/is not encoded as valid utf8/,
        "Check that bogus UTF8 generates an exception";
}

HASHES: {
    my $hub = create_test_hub();
    my $ws = $hub->current_workspace;
    my $creator = $hub->current_user;
    my $editor = create_test_user();
    $ws->add_user(user => $editor);

    my $date = DateTime->new(
        year => 2011, month => 1, day => 1,
        hour => 0, minute => 0, second => 0,
        time_zone => 'UTC',
    );
    my $edit = DateTime->new(
        year => 2011, month => 1, day => 23,
        hour => 0, minute => 0, second => 0,
        time_zone => 'UTC',
    );
    my $mtime = $edit->epoch;

    my $page = Socialtext::Page->new( hub => $hub )->create(
        title => 'Testing Hashes, Yo',
        date => $date,
        content => 'foo',
    );

    $hub->current_user($editor);
    $page->edit_rev(editor => $editor, edit_time => $edit);
    $page->edit_summary('changing to bar');
    $page->content('bar');
    $page->tags(['FOO','Bar']);
    $page->store(user => $editor);

    is $page->revision_count, 2;

    $page = $hub->pages->new_from_name('testing_hashes_yo');

    $hub->current_user($creator);

    my $page_hash = $page->to_hash;
    cmp_deeply $page_hash, {
        create_time     => '2011-01-01 00:00:00 GMT',
        creator         => $creator->email_address,
        creator_id      => $creator->user_id,
        edit_summary    => 'changing to bar',
        last_edit_time  => '2011-01-23 00:00:00 GMT',
        last_editor     => $editor->email_address,
        last_editor_id  => $editor->user_id,
        locked          => 0,
        modified_time   => $mtime,
        name            => 'Testing Hashes, Yo',
        page_id         => 'testing_hashes_yo',
        page_uri        => re('^https?.+testing_hashes_yo$'),
        revision_count  => 2,
        revision_id     => re('^\d+\.\d+$'),
        revision_num    => 2,
        summary         => 'bar',
        tags            => [ 'FOO', 'Bar' ],
        type            => 'wiki',
        uri             => 'testing_hashes_yo',
        workspace_name  => $ws->name,
        workspace_title => $ws->title,
    }, 'page hash'; 

    my $md_hash = $page->legacy_metadata_hash;
    cmp_deeply $md_hash, {
        'Revision-Summary' => 'changing to bar',
        Category           => [ 'FOO', 'Bar' ],
        Date               => '2011-01-23 00:00:00 GMT',
        Encoding           => 'utf8',
        From               => $editor->email_address,
        Locked             => 0,
        Revision           => 2,
        Subject            => 'Testing Hashes, Yo',
        Summary            => 'bar',
        Type               => 'wiki',
    }, 'md hash';
}
