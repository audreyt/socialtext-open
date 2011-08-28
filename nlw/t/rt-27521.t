#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

# Test Exception RT 27521
#
# While rendering a page with search WAFL (e.g. {search: foo workspace:blah})
# the code would sometimes lose track of the current_workspace.  This is b/c
# the wafl rendering code keeps changing the current_workspace, but in some
# cases would forget to change it back.  The particular case we found (and
# which is tested here) is when a deleted page was found.  The rendering code
# would bail when a deleted page was found w/o setting current_workspace back
# to its original value.
#
# Basic testing strategy:
#
#    create two workspaces: foo and bar
#    add $page w/ $term in foo
#    wait for index of $page in foo
#    add a $new_page in bar which queries: {search $term workspaces:foo}
#    render $new_page
#    delete $page in foo
#    wait for index of $page in foo
#    render $new_page
#    check value of current_workspace on hub is foo

use mocked 'Apache::Cookie';
use Test::Socialtext tests => 11;

BEGIN { use_ok("Socialtext::Search::Solr::Factory") }
fixtures(qw(admin foobar));

our $term_hub = new_hub('admin');
our $wafl_hub = new_hub('foobar');

make_page_ok( $term_hub, "Term Page", "morlangoo foo blah baz" );
make_page_ok( $wafl_hub, "Wafl Page", "{search: morlangoo workspaces:admin}" );

my $term_page = Socialtext::Page->new( hub => $term_hub, id => "term_page" );
my $wafl_page = Socialtext::Page->new( hub => $wafl_hub, id => "wafl_page" );

render_ok( $wafl_hub, $wafl_page, qr/Search for morlangoo workspaces:admin/ );

$term_page->delete( user => $term_hub->current_user );

index_ok( $term_hub, $term_page->id );
render_ok( $wafl_hub, $wafl_page, qr/Search for morlangoo workspaces:admin/ );
is( $wafl_hub->current_workspace->name, "foobar",
    "Ensuring workspace is same after rendering WAFL page" );

sub render_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ( $hub, $page, $rx, $msg ) = @_;
    $hub->pages->current($page);
    my $g = $hub->pages->ensure_current($page);
    my $output = eval { $hub->display->display() };
    like( $output, $rx, $msg );
}

sub make_page_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $hub, $title, $content, $tags ) = @_;
    my $page = $hub->pages->new_from_name($title);
    $page->edit_rev();
    $page->update(
        user        => $hub->current_user,
        content_ref => \$content,
        subject => $title,
        revision => $page->revision_num,
    );
    ok $page->exists, "made page $title";

    my $p2 = $hub->pages->new_page($page->page_id);
    ok $p2->exists, "new_page() exists";

    index_ok( $hub, $page->page_id );
    return $page;
}

sub index_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $INDEX_MAX = 60*5;    # Maximum of 5 minutes to index page.

    my ( $hub, $page ) = @_;
    my $id   = ref($page) ? $page->page_id : $page;

    # Use a double eval in case the alarm() goes off in between returing from
    # the inner eval and before alarm(0) is executed.
    my $fail;
    eval {
        local $SIG{ALRM} = sub {
            die "Indexing $id is taking more than $INDEX_MAX seconds.\n";
        };
        alarm($INDEX_MAX);
        eval { 
            indexer($hub)->index_page($id);
        };
        $fail = $@;
        alarm(0);
    };

    diag("ERROR Indexing $id: $fail\n") if $fail;
    ok( not($fail), "Indexing $id" );
}

sub indexer {
    my $hub = shift;
    my $ws  = $hub->current_workspace;
    return Socialtext::Search::Solr::Factory->create_indexer($ws->name);
}
