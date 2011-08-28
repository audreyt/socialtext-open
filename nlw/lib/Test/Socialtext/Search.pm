# @COPYRIGHT@
package Test::Socialtext::Search;
use strict;
use warnings;

use Data::Dumper;
use File::Path;
use File::Spec;
use Test::More;
use Test::Socialtext ();
use Test::Socialtext::Environment;
use Socialtext::AppConfig;
use Socialtext::Jobs;
use Socialtext::Paths;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(init delete_page search_for_term
                 search_for_term_in_attach confirm_term_in_result
                 create_and_confirm_page);

if (Socialtext::AppConfig->syslog_level ne 'debug') {
    Socialtext::AppConfig->set('syslog_level' => 'debug');

    # if this is call on the first test run, $file won't exist, so be explicit
    # when saving.
    my $file = Socialtext::AppConfig->test_dir() 
        . "/etc/socialtext/socialtext.conf";
    Socialtext::AppConfig->write(file => $file);
}

sub hub {
    return Test::Socialtext::main_hub();
};

sub delete_page {
    my $title = shift;
    my $hub   = hub();
    my $page = $hub->pages->new_from_name($title);
    $page->delete( user => $hub->current_user );
}

sub search_for_term {
    my $term = shift;
    my $negation = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    Test::Socialtext::ceqlotron_run_synchronously();

    my $hub    = hub();
    my $search = $hub->search;
    $search->sortby('relevance');
    $search->search_for_term(search_term => $term);
    my $set = $search->result_set;

    if ($negation) {
        ok( $set, 'we have results' );
        is_deeply(
            $set->{rows},
            [],
            "result set found no hits $term"
        );
        if (@{ $set->{rows} }) {
            warn Dumper $set->{rows};
        }
    } else {
        ok( $set, 'we have results' );
        ok( $set->{hits} > 0, 'result set found hits' );
        confirm_term_in_result($hub, $term, $set->{rows}->[0]->{page_uri});
        like( $set->{rows}->[0]->{Date}, qr/\d+/,
            'date has some numbers in it');
        like( $set->{rows}->[0]->{DateLocal}, qr/\d+/,
            'date local has some numbers in it');
    }
}

# XXX refactor to remove the dreaded duplication
# XXX add actually looking inside the attachments to confirm
sub search_for_term_in_attach {
    my $term = shift;
    my $filename = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    Test::Socialtext::ceqlotron_run_synchronously();

    my $hub    = hub();
    my $search = $hub->search;
    $search->search_for_term(search_term => $term);
    my $set = $search->result_set;
    ok( $set->{hits} > 0, "have page hits via term $term");
    ok( grep($_->{is_attachment}, @{$set->{rows}}), "have attachments");
    is( $set->{rows}->[0]->{document_title}, $filename,
        "found right file: $filename");
}

sub confirm_term_in_result {
    my $hub = shift;
    my $term = shift;
    my $page_uri = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    unless (defined $page_uri) {
        fail("name, content or tag contains correct term ($term)");
        return;
    }

    my $page = $hub->pages->new_from_name($page_uri);
    my $name = $page->name;
    my $body_ref = $page->body_ref;
    my $tags = $page->tags;
    $term =~ s/^(?:tag|category|title)://;
    $term =~ s/^=//;
    $term =~ s/^"//;
    $term =~ s/"$//;

    ok(
        ($name =~ /$term/i or
        $$body_ref =~ /$term/i or
        grep(/\b$term\b/i, @$tags)),
        "name, content or tag contains correct term ($term)"
    );
}


sub create_and_confirm_page {
    my $title = shift;
    my $content = shift;
    my $categories = shift || [];
    my $hub = hub();

    # FIXME: $categories goes in as a reference to a
    # list. It can be here as [] and come out the other
    # side as ('Recent Changes') because there is
    # code down inside CategoryPlugin that is manipulates
    # the list ref
    Socialtext::Page->new(hub => $hub)->create(
        title => $title,
        content => "$content\n",
        categories => $categories,
        creator    => $hub->current_user,
    );

    {
        my $pages  = $hub->pages;
        my $page   = $pages->new_from_name($title);
        ok( $page->exists, 'a test page exists' );
        like( $page->content, qr{$content},
            'page content is correct');
        if (@$categories) {
            my $page_categories = $page->tags;
            foreach my $category (grep !/recent changes/i, @$categories) {
                ok((grep /\b$category\b/i, @$page_categories),
                    "page is in $category");
            }
        }
    }
}


1;
