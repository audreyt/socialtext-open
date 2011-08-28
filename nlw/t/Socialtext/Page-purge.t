#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 9;
use Test::Socialtext::Fatal;
use Socialtext::SQL qw/sql_singlevalue/;
fixtures(qw(no-ceq-jobs db));

my $hub = create_test_hub();

my $upload_id;
attach: {
    my $page = $hub->pages->new_from_name('Goes Boom');
    $page->content("boom!");
    $page->tags(["Welcome"]);
    $page->store();

    open my $fh, '<', 't/attachments/socialtext-logo-30.gif';
    my $att = $hub->attachments->create(
        page => $page,
        fh => $fh,
        filename => 'logo.gif',
        mime_type => 'image/gif',
        embed => 1,
    );
    $upload_id = $att->upload->attachment_id;
    ok $upload_id;

    my $page_clone = $hub->pages->new_from_name('Goes Boom');
    my ($att_clone) = $page_clone->attachments;
    isa_ok $att_clone, 'Socialtext::Attachment';
    like $page_clone->content, qr/\Q{image: logo.gif}/, "inlined";

    my $count = sql_singlevalue(q{
        SELECT COUNT(1) FROM page_attachment WHERE page_id = ? AND workspace_id = ?}, 'goes_boom', $hub->current_workspace->workspace_id);
    is $count, 1, "page_attachment exists";

    $count = sql_singlevalue(q{
        SELECT COUNT(1) FROM attachment WHERE attachment_id = ?
    }, $upload_id);
    is $count, 1, "attachment exists";
}

purge: {
    my $page = $hub->pages->new_from_name('Goes Boom');
    $page->purge();

    my @pages = $hub->category->get_pages_for_category('Welcome');
    my $is_in_category = grep { $_->title eq 'Goes Boom' } @pages;
    ok !$is_in_category, '"Goes Boom" is not in Welcome category';

    my $count = sql_singlevalue(q{
        SELECT COUNT(1) FROM page_attachment WHERE page_id = ? AND workspace_id = ?}, 'goes_boom', $hub->current_workspace->workspace_id);
    is $count, 0, "page_attachment purged";

    $count = sql_singlevalue(q{
        SELECT COUNT(1) FROM attachment WHERE attachment_id = ?
    }, $upload_id);
    is $count, 0, "attachment purged";

    like exception {
        my $upload = Socialtext::Upload->Get(attachment_id => $upload_id);
    }, qr/Uploaded file not found\./, "can't load the Upload object";
}

