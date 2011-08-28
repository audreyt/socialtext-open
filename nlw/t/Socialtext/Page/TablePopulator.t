#!perl
use warnings;
use strict;
use 5.12.2;

use Test::Socialtext tests => 30;
use Test::Socialtext::Fatal;
use Test::Deep;
use Socialtext::SQL qw/:exec/;
use List::Util qw/shuffle/;
use Cwd;
use ok 'Socialtext::Page::TablePopulator';

fixtures('db');

only_these_things_reference_page_id: {
    my $sth = sql_execute(q{
        SELECT DISTINCT constraint_name
        FROM information_schema.referential_constraints
        NATURAL JOIN information_schema.constraint_table_usage
        NATURAL JOIN information_schema.constraint_column_usage
        WHERE table_name = 'page' AND column_name = 'page_id'
        ORDER BY constraint_name
    });
    my @constraints = map { $_->[0] } @{$sth->fetchall_arrayref||[]};

    # If anything else references the page table, be sure to preserve those
    # too in TablePopulator (it would be really nice of you to also check that
    # in this test).  Sincerely, ~stash
    cmp_deeply \@constraints, [qw(
        event_page_fk
        page_link__from_page_id_fk
        page_tag_workspace_id_page_id_fkey
        user_like_page_id_fk
    )], "no additional fk constraints on page";
}

my $hub = create_test_hub();
my $ws = $hub->current_workspace;
my $ws_id = $ws->workspace_id;
my $user = create_test_user(unique_id => '1299022686305310');
$ws->add_user(user => $user, role => 'admin');
$hub->current_user($user);

# in order to match with what's in the tarball:
local $Socialtext::PageRevision::NextRevisionID = 20110301000000;

my ($p0, $p1, $p2, $p3);
is exception {
    $user->primary_account->enable_plugin('signals');

    $p0 = $hub->pages->new_from_name("Referenced Page");
    $p0->content("Meh\n");
    $p0->store;

    $p1 = $hub->pages->new_from_name("Test Page");
    $p1->content("Page Content [Referenced Page]\n");
    $p1->tags(['Awesome','sauce']);
    $p1->store;
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_save',
        page => $p1,
    });
    is $p1->revision_num, 1, "1st display revision";

    $p1->update_from_remote(
        content =>
            "Updated to cause a signal-event, link to [Referenced Page]\n",
        edit_summary => 
            'Woot {link: '.$ws->name.' ['.$p1->page_id.']} yeah',
        signal_edit_to_network => 'account-'.$user->primary_account_id,
        signal_edit_summary => 1,
    );
    is $p1->revision_num, 2, "2nd display revision";

    # delete and un-delete
    my $old_revision_id = $p1->revision_id;
    $p1->delete(user => $hub->current_user);
    $p1->restore_revision(revision_id => $old_revision_id,
        user => $hub->current_user);

    is $p1->revision_num, 2, "back to 2nd display revision";
    is $p1->revision_count, 4, "4th overall revision";

    $p2 = $hub->pages->new_from_name("To Delete");
    $p2->content("Goodbye\n");
    $p2->store;
    my $att = $hub->attachments->create(
        page => $p2,
        fh => 't/attachments/grayscale.png',
        filename => 'GRAY2DELETE.png',
        mime_type => 'image/png',
    );
    # for tarball consistency:
    sql_execute(q{
        UPDATE page_attachment SET id = ?
        WHERE attachment_id = ?
    }, '20110301233806-0-30531', $att->attachment_id);

    $p3 = $hub->pages->new_from_name("To Purge");
    $p3->content("So-long\n");
    $p3->store;
    $hub->attachments->create(
        page => $p3,
        fh => 't/attachments/grayscale.png',
        filename => 'GRAY2PURGE.png',
        mime_type => 'image/png',
    );

    $hub->breadcrumbs->drop_crumb($_) for shuffle ($p0,$p1,$p2,$p3);

    sql_execute(q{
        UPDATE page SET views = views+10 WHERE workspace_id = ?
    }, $ws_id);
}, undef, "set up pages and events";

my $sig_id;
check_events: {
    my $event_sth = sql_execute(q{
        SELECT * FROM event WHERE event_class='page' 
        AND page_workspace_id = ? AND page_id = ?
        ORDER BY at DESC
    }, $ws_id, $p1->page_id);
    my $all = $event_sth->fetchall_arrayref({});

    cmp_deeply $all, [
        superhashof({
            event_class => 'page',
            action => 'delete',
            page_id => $p1->page_id,
        }),
        superhashof({
            event_class => 'page',
            action => 'edit_save',
            page_id => $p1->page_id,
            signal_id => re('\d+'),
        }),
        superhashof({
            event_class => 'page',
            action => 'edit_save',
            page_id => $p1->page_id,
            signal_id => undef,
        })
    ], "got page events for that page";

    $sig_id = $all->[1]{signal_id};
}

check_signal: {
    my $sig = Socialtext::Signal->Get(signal_id => $sig_id);
    isa_ok $sig, 'Socialtext::Signal', "edit made a signal";
}

check_links: {
    my $link_sth = sql_execute(q{
        SELECT to_workspace_id, to_page_id
          FROM page_link
         WHERE from_workspace_id = ? AND from_page_id = ?
    }, $ws_id, $p1->page_id);
    is $link_sth->rows, 1, '"test page" has a fk-reference from page_link';
    my $links = $link_sth->fetchall_arrayref({});
    cmp_deeply $links,
        [{to_workspace_id => $p0->workspace_id, to_page_id => $p0->page_id}],
        "test page links to referenced page";
}

check_tags: {
    my $tag_sth = sql_execute(q{
        SELECT array_accum(tag)
          FROM page_tag
         WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $p1->page_id);
    is $tag_sth->rows, 1, '"test page" has a fk-reference from page_tag';
    my $tags = $tag_sth->fetchrow_arrayref();
    cmp_deeply $tags,
        [set('Awesome','sauce')], # unordered
        "test page has tags (page_tag table)";

    my $tag2_sth = sql_execute(q{
        SELECT tags FROM page
         WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $p1->page_id);
    my $tags2 = $tag2_sth->fetchrow_arrayref();
    cmp_deeply $tags2,
        [set('Awesome','sauce')], # unordered
        "test page has tags (page table)";
}

# create a new page
# delete a page
# purge a page
# add attachment
# delete attachment
# purge attachment
# change number of views for a page
# add a tag (possum)
# remove a tag (sauce)

recreate: {
    my $cwd = getcwd();
    is exception {
        my $dir = File::Temp->newdir;
        my $tarball = "$cwd/t/test-data/tablepop-updated.1.tar.gz";
        ok !system("cd $dir; tar zxf $tarball"), "extracted import tarball";

        my $tpop = Socialtext::Page::TablePopulator->new(
            workspace_name => $ws->name,
            old_name => "tablepop-updated",
            data_dir => "$dir",
        );
        $tpop->populate(recreate => 1);
        is $cwd, getcwd(), "cwd was unchanged";
    }, undef, "repopulated";
    chdir $cwd; # in case it fails
}

# the event_page_fk constraint
recheck_events: {
    my $event_sth = sql_execute(q{
        SELECT * FROM event WHERE event_class='page' 
        AND page_workspace_id = ? AND page_id = ?
        ORDER BY at DESC
    }, $ws_id, $p1->page_id);
    my $all = $event_sth->fetchall_arrayref({});

    cmp_deeply $all, [
        superhashof({
            event_class => 'page',
            action => 'delete',
            page_id => $p1->page_id,
        }),
        superhashof({
            event_class => 'page',
            action => 'edit_save',
            page_id => $p1->page_id,
            signal_id => $sig_id,
        }),
        superhashof({
            event_class => 'page',
            action => 'edit_save',
            page_id => $p1->page_id,
            signal_id => undef,
        })
    ], "recheck: page events untouched";
}

# the page_link__from_page_id_fk constraint
recheck_links: {
    my $link_sth = sql_execute(q{
        SELECT to_workspace_id, to_page_id
          FROM page_link
         WHERE from_workspace_id = ? AND from_page_id = ?
    }, $ws_id, $p1->page_id);
    is $link_sth->rows, 1, '"test page" has a fk-reference from page_link';
    my $links = $link_sth->fetchall_arrayref({});
    cmp_deeply $links,
        [{to_workspace_id => $p0->workspace_id, to_page_id => $p0->page_id}],
        "recheck: test page links to referenced page still";
}

# the page_tag_workspace_id_page_id_fkey constraint
recheck_tags: {
    my $tag_sth = sql_execute(q{
        SELECT array_accum(tag)
          FROM page_tag
         WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $p1->page_id);
    is $tag_sth->rows, 1, '"test page" has a fk-reference from page_tag';
    my $tags = $tag_sth->fetchrow_arrayref();
    cmp_deeply $tags,
        [set('Awesome','possum')], # unordered
        "recheck: test page has page_tags updated";

    my $tag2_sth = sql_execute(q{
        SELECT tags
          FROM page
         WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $p1->page_id);
    my $tags2 = $tag2_sth->fetchrow_arrayref();
    cmp_deeply $tags2,
        [set('Awesome','possum')], # unordered
        "recheck: test page has tags updated";
}

recheck_views: {
    my $views = sql_singlevalue(q{
        SELECT views FROM page WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, $p1->page_id);
    is $views, 12, "recheck: views got updated from COUNTER";
}

recheck_crumbs: {
    # these should be totally different in the tarball than p3 p2 p1 p0
    my $sth = sql_execute(q{
        SELECT page_id
          FROM breadcrumb
         WHERE viewer_id = ? AND workspace_id = ?
         ORDER BY last_viewed DESC
    }, $user->user_id, $ws_id);
    my @pages = map { $_->[0] } @{$sth->fetchall_arrayref || []};
    cmp_deeply \@pages, [qw(to_purge to_delete referenced_page test_page)],
        "recheck: breadcrumbs overwritten";
}

recheck_purged_deleted: {
    my $is_deleted = sql_singlevalue(q{
        SELECT deleted FROM page WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, 'to_delete');
    is $is_deleted, 1, "recheck: page was deleted on repop";

    my $exists = sql_singlevalue(q{
        SELECT COUNT(*) FROM page WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, 'to_purge');
    ok !$exists, "recheck: purged page was purged";
}

recheck_attachments: {
    my $is_deleted = sql_singlevalue(q{
        SELECT deleted FROM page_attachment
        WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, 'to_delete');
    is $is_deleted, 1, "recheck: page attachment was deleted on repop";

    my $exists = sql_singlevalue(q{
        SELECT COUNT(*) FROM page_attachment
        WHERE workspace_id = ? AND page_id = ?
    }, $ws_id, 'to_purge');
    ok !$exists, "recheck: purged page had attachment purged";
}

pass 'done';
