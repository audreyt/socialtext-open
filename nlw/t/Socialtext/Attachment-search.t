#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Differences;
use Test::Socialtext;
use Test::Exception;
use Socialtext::Attachment;
use Fcntl ':seek';
use File::Temp;

fixtures(qw(db no-ceq-jobs));

my $user = create_test_user;
my $workspace = create_test_workspace;
my $hub = create_test_hub;
$hub->current_user($user);
$hub->current_workspace($workspace);

setup: {
    my $page_data = [
        {
            name=>'Page One',
            id=>'page_one',
            content=>'Page with attachments',
            attachments => [
                {name=>'text_01.txt', content=>'test one odd'},
                {name=>'text_02.txt', content=>'test two'},
            ],
        },
        {
            name=>'Page Two',
            id=>'page_two',
            content=>'page with attachments',
            attachments => [
                {name=>'text_words_03.txt', content=>'test three words odd'},
                {name=>'text_words_04.txt', content=>'test words four'},
            ],
        },
    ];
    load_page($hub, $_) for (@$page_data);

    ceqlotron_run_synchronously();
}

requires_workspace: {
    dies_ok { 
        Socialtext::Attachment->Search(
            search_term => 'NOSUCH',
        );
    } "search dies without 'workspace' or 'workspace_name' param";

    lives_ok {
        Socialtext::Attachment->Search(
            search_term => 'NOSUCH',
            workspace => $workspace,
        );
    } "search lives with 'workspace' param";

    lives_ok {
        Socialtext::Attachment->Search(
            search_term => 'NOSUCH',
            workspace_name => $workspace->name,
        );
    } "search lives with 'workspace_name' param";
}

test_one_page: {
    my $page = 'page_one';
    my ($term,$expected);

    $term = 'test';
    $expected = [qw(text_01.txt text_02.txt)];
    do_test($hub, $term, $expected, $page);

    $term = 'one';
    $expected = [qw(text_01.txt)];
    do_test($hub, $term, $expected, $page);

    $term = 'filename:text';
    $expected = [qw(text_01.txt text_02.txt)];
    do_test($hub, $term, $expected, $page);

    $term = 'filename:02';
    $expected = [qw(text_02.txt)];
    do_test($hub, $term, $expected, $page);
}

test_workspace: {
    my ($term,$expected);

    $term = 'one';
    $expected = [qw(text_01.txt)];
    do_test($hub, $term, $expected);

    $term = 'three';
    $expected = [qw(text_words_03.txt)];
    do_test($hub, $term, $expected);

    $term = 'odd';
    $expected = [qw(text_01.txt text_words_03.txt)];
    do_test($hub, $term, $expected);

    $term = 'test';
    $expected = [qw(text_01.txt text_02.txt
                    text_words_03.txt text_words_04.txt)];
    do_test($hub, $term, $expected);
    
    $term = 'words';
    $expected = [qw(text_words_03.txt text_words_04.txt)];
    do_test($hub, $term, $expected);

    $term = 'filename:03';
    $expected = [qw(text_words_03.txt)];
    do_test($hub, $term, $expected);

    $term = 'filename:01';
    $expected = [qw(text_01.txt)];
    do_test($hub, $term, $expected);

    $term = 'filename:words';
    $expected = [qw(text_words_03.txt text_words_04.txt)];
    do_test($hub, $term, $expected);

    $term = 'filename:text';
    $expected = [qw(text_01.txt text_02.txt
                    text_words_03.txt text_words_04.txt)];
    do_test($hub, $term, $expected);
}

done_testing;
exit;
################################################################################

sub do_test {
    my $hub = shift;
    my $term = shift;
    my $expected = shift;
    my $page = shift; # may be undef

    my $exp = scalar(@$expected);
    my ($atts,$count) = do_search($hub, $term => $page);
    is $count, $exp, "found $exp attachment(s) for term '$term'";
    eq_or_diff $atts, $expected, '... correct attachment(s)';
}

sub do_search {
    my $hub = shift;
    my $term = shift;
    my $page = shift;

    diag $page ? "Searching page '$page'" : "Searching workspace";
    my ($hits,$hit_count) = Socialtext::Attachment->Search(
        search_term => $term,
        workspace => $workspace,
        $page ? (page_id => $page) : (),
    );

    return (names_from_hits($hub, $hits), $hit_count);
}

sub names_from_hits {
    my $hub = shift;
    my $hits = shift;

    return [
        sort map { $hub->attachments->load(
            id => $_->attachment_id,
            page_id => $_->page_uri,
        )->filename } @$hits
    ];
}

sub load_page {
    my $hub = shift;
    my $data = shift;

    my $page = $hub->pages->new_from_name($data->{name});
    $page->edit_rev;
    $page->update(
        content_ref => \$data->{content},
        revision => $page->revision_num,
        subject => $data->{name},
        user => $user,
    );

    load_attachment($hub, $page, $_) for (@{$data->{attachments}});

    my $fresh = $hub->pages->new_from_uri($data->{name});
    ok $fresh, "Page $data->{name} exists";
    isa_ok $fresh, 'Socialtext::Page';

    my @atts = $fresh->attachments;
    my $expected = scalar(@{$data->{attachments}});
    is scalar(@atts), $expected, "Page has $expected attachments";
}

sub load_attachment {
    my $hub = shift;
    my $page = shift;
    my $data = shift;

    my $fh = File::Temp->new();
    print $fh $data->{content};
    seek $fh, 0, SEEK_SET;
    my $att = $hub->attachments->create(
        filename => $data->{name},
        fh => $fh,
        creator => $user,
        Content_type => 'text/plain',
        page => $page,
        embed => 0,
    );
}
