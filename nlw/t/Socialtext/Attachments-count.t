#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 8;
use Test::Socialtext::Fatal;
fixtures('db');

use ok 'Socialtext::Attachments';
use ok 'Socialtext::Page';
use ok 'Socialtext::String';

my $hub = create_test_hub();
my $ws_name = $hub->current_workspace->name;

# test that attachments on a deleted page do not show up on
# a list of all pages

my $page = $hub->pages->new_from_name("Test Page");
$page->content('meh');
$page->store();

my $all_attachments_count_before = count_all_attachments();
ok !$hub->attachments->attachment_exists($ws_name, 'test_page', 'foo.txt'), 'attachment_exists false';

is exception {
    my $filename = 't/attachments/foo.txt';
    open my $fh, '<', $filename or die "$filename: $!";
    $hub->attachments->create(
        filename => $filename,
        page => $page,
        fh       => $fh,
    );
}, undef, "created attachment";

ok $hub->attachments->attachment_exists($ws_name, 'test_page', 'foo.txt'), 'attachment_exists true';
my $all_attachments_count_middle = count_all_attachments();
$page->delete(user => $hub->current_user);
my $all_attachments_count_after = count_all_attachments();

is(
    $all_attachments_count_middle - 1, $all_attachments_count_before,
    'adding one attachment increase attachment count by one'
);
is(
    $all_attachments_count_after, $all_attachments_count_before,
    'deleting a page decreases attachment count'
);

sub count_all_attachments {
    # Please don't count attachments like this in production code; please
    # write a count_attachments_in_workspace() or something:
    my $attachments = $hub->attachments->all_attachments_in_workspace();
    return scalar @$attachments;
}
