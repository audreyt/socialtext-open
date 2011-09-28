#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use mocked 'Socialtext::Events';
use Test::Socialtext tests => 43;
use ok 'Socialtext::Page';

fixtures(qw( db ));

my $hub = create_test_hub();
my $ws = $hub->current_workspace;
my $editor = create_test_user(username_isnt_email => 1);
my $creator = create_test_user(username_isnt_email => 1);
$ws->add_user(user => $editor);
$ws->add_user(user => $creator);
isnt $editor->username, $editor->email_address, "username != email_address";
isnt $hub->current_user->user_id, $editor->user_id, "have to be different";

my ($ws_id, $ws_name, $ws_title) = map { $ws->$_ } qw(workspace_id name title);

Create_from_row: {
    my $data = {
        anno_blob => undef,
        workspace_id => $ws_id,
        workspace_name => $ws_name,
        workspace_title => $ws_title,
        page_id => 'some_page_id',
        name => 'Some Page ID',
        last_editor_id => $editor->user_id,
        last_edit_time_utc => '2008-01-01 23:12:01Z',
        creator_id => $creator->user_id,
        create_time_utc => '2007-01-01 23:12:01Z',
        current_revision_id => 1234,
        current_revision_num => 42,
        revision_count => 987,
        page_type => 'wiki',
        deleted => 1,
        summary => 'summary',
        edit_summary => 'edit summary',
        tags => ['tag'],
        junk => 'junk',
        views => 123_456,
        exists => 0, # should get overridden
        hub => $hub,
        like_count => 0,
    };
    my $page = Socialtext::Page->_new_from_row($data);
    isa_ok $page, 'Socialtext::Page';
    ok $page->exists, "since it's new_from_row, it exists";
    ok $page->has_rev, "don't need to lazy-load the PageRevision";
    isa_ok $page->rev, "Socialtext::PageRevision", "recreated a rev object";
    is $page->revision_id, 1234;
    is $page->rev->revision_id, 1234;

    is $page->title, 'Some Page ID';
    is $page->id, 'some_page_id';
    is $page->uri, 'some_page_id';
    is $page->summary, 'summary';
    is $page->edit_summary, 'edit summary';
    is_deeply $page->tags, ['tag'];
    isa_ok $page->hub, 'Socialtext::Hub';

    is $page->last_edited_by->user_id, $editor->user_id;
    is $page->creator->user_id, $creator->user_id;
    is $page->last_editor_id, $editor->user_id;
    is $page->creator_id, $creator->user_id;

    # to_result() is used to format pages into a row returned to a listview
    # many of these fields are named after the mime-like file format
    is_deeply $page->to_result, {
        annotations => [],
        Date => '2008-01-01 23:12:01 GMT',
        DateLocal => 'Jan 1, 2008 3:12pm',
        Deleted => 1,
        From => $editor->email_address,
        Locked => 0,
        Revision => 42,
        Subject => 'Some Page ID',
        Summary => 'summary',
        Type => 'wiki',
        create_time => '2007-01-01 23:12:01 GMT',
        create_time_local => 'Jan 1, 2007 3:12pm',
        creator => $creator->username,
        edit_summary => 'edit summary',
        is_spreadsheet => '',
        page_id => 'some_page_id',
        page_uri => 'some_page_id',
        revision_count => 987,
        username => $editor->username,
        workspace_name => $ws_name,
        workspace_title => $ws_title,
    };

    my $hash = $page->hash_representation;
    like delete $hash->{page_uri},
        qr{/\Q$ws_name\E/(?:index\.cgi\?)?some_page_id$},
        "page_uri is the full_uri() function";
    is_deeply $hash, {
        annotations     => [],
        create_time     => '2007-01-01 23:12:01 GMT',
        creator         => $creator->email_address,
        creator_id      => $creator->user_id,
        deleted         => 1,
        edit_summary    => 'edit summary',
        last_edit_time  => '2008-01-01 23:12:01 GMT',
        last_editor     => $editor->email_address,
        last_editor_id  => $editor->user_id,
        locked          => 0,
        modified_time   => 1199229121,     # edit time as epoch-seconds
        name            => 'Some Page ID',
        page_id         => 'some_page_id',
        revision_count  => 987,
        revision_id     => 1234,
        revision_num    => 42,
        summary         => 'summary',
        tags            => ['tag'],
        type            => 'wiki',
        uri             => 'some_page_id',
        workspace_name  => $ws_name,
        workspace_title => $ws_title,
    }, 'hash_representation is as expected';

    ok !$page->mutable;
    my $old_rev = $page->rev;
    my $rev = $page->edit_rev(editor => $hub->current_user);
    is $page->prev_rev, $old_rev, "can roll-back to orig revision";
    ok $page->mutable;
    $page->add_tag('zed');
    $page->add_tag('abba');
    is_deeply $page->tags, [qw/tag zed abba/], 'original tag order';
    is_deeply [ $page->tags_sorted ], [qw/abba tag zed/], 'sorted tag order';

    $Socialtext::Page::DISABLE_CACHING = 1;
    is $page->to_html, <<EOT, "to_html has default content";
<div class="wiki">
Replace this text with your own.   </div>
EOT

    $page->content("foo content\n");
    is $page->content, "foo content\n", "content ok";
    is ${$page->body_ref}, "foo content\n", "body_ref ok too";

    is $page->to_absolute_html, <<EOT, "to_absolute_html";
<div class="wiki">
<p>
foo content</p>
</div>
EOT
    is $page->to_html, <<EOT, "to_html";
<div class="wiki">
<p>
foo content</p>
</div>
EOT

    # destructive tests
    ok !$page->is_spreadsheet;
    $page->page_type('spreadsheet');
    ok $page->is_spreadsheet;

    cancel_edit: {
        $page->rev($old_rev);
        ok !$page->mutable, "page edit cancelled";
        is $page->revision_id, $page->rev->revision_id;

        is_deeply $page->tags, [qw/tag/], "tags reset";
        is $page->last_editor_id, $editor->user_id, "editor reset";
        is $page->creator_id, $creator->user_id, "creator says the same";
        is $page->content, '', "content reset";
        ok !$page->is_spreadsheet, "no longer a spreadsheet";
    }
}

pass 'done';
