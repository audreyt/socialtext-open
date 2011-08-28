#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 32;
use Readonly;

fixtures(qw(db));

my $hub = create_test_hub();
isa_ok( $hub, 'Socialtext::Hub' ) or die;

my $pages = $hub->pages;
isa_ok( $pages, 'Socialtext::Pages' ) or die;

{
    Readonly my $TITLE => 'William Morris';
    Readonly my $CREED => <<END_OF_CREED;
Have nothing in your houses that you do not know to be useful or
believe to be beautiful.
END_OF_CREED
    Readonly my $RANT  => <<END_OF_RANT;
In literature, they try to avoid saying the same word twice.  He could
have just as easily said, "Have nothing in your houses that you do not
believe to be useful or know to be beautiful."  You take things too
literally, and you can quote me on that.
--- Contributed by ingus
END_OF_RANT

    my $page = $hub->pages->new_from_name($TITLE);
    ok !$page->exists, "doesn't exist yet";
    $page->body_ref(\$CREED);
    $page->store();

    isa_ok( $page, "Socialtext::Page" );
    is $page->revision_count, 1, 'Fresh page has exactly 1 revision id.';
    is $page->revision_num, 1, 'Fresh page is Revision 1';
    ok $page->exists, "now it exists";
    my $creed_summary = $page->summary;
    like $creed_summary, qr/^have nothing/i;

    my $original_revision_id = $page->revision_id;
    ok $original_revision_id;

    # Replace the creed with the rant.
    $page->edit_rev();
    $page->body_ref(\$RANT);
    $page->store();
    my $rant_summary = $page->summary;
    like $rant_summary, qr/^in literature/i;
    isnt $page->revision_id, $original_revision_id, "revision id is new";

    # Should have two revisions now
    my @revision_ids = $page->all_revision_ids;
    is scalar @revision_ids, 2,
        '$page->store adds a revision id.';

    # reload the page object via current
    $page = $pages->current( $pages->new_from_name($TITLE) );
    isa_ok( $page, "Socialtext::Page" );
    is $page->content, $RANT, 'rant loaded';
    is $page->summary, $rant_summary, "rant summary";

    is_deeply [ $page->all_revision_ids ], \@revision_ids,
        'new_from_name produces the same revision ids';
    is $page->revision_num, 2, 'metadata is Revision 2';

    $page->switch_rev($original_revision_id);
    is $page->revision_id, $original_revision_id, 'revision_id setter works.';
    is $page->revision_num, 1, 'that revision was lazy-loaded';
    is $page->content, $CREED, 'After switching, creed is loaded';
    is $page->summary, $creed_summary, "creed summary";

    is_deeply [ $page->all_revision_ids ], \@revision_ids,
        'loading old content does not molest the revision id list.';

    $page = $pages->current( $pages->new_from_name($TITLE) );
    $page->restore_revision(
        revision_id => $original_revision_id,
        user        => $hub->current_user,
    );

    @revision_ids = $page->all_revision_ids;
    is scalar @revision_ids, 3,
        '$page->store adds a revision id.';
    is $page->revision_num, 1, 'After load/store, Revision no. is 1.';
    ok $page->revision_id != $original_revision_id,
        '$page->store updates revision_id';
    is $page->content, $CREED, 'After load/store, page content is restored.';
    is $page->summary, $creed_summary, "creed summary";

    my $changes = $hub->recent_changes
        ->get_recent_changes_in_category(limit => 1);

    my $row = $changes->{rows}->[0];
    is($row->{Subject}, $TITLE, "most recently modified page is $TITLE" );
    is($row->{Revision}, 1, 'recent_changes revision number is restored.');
    is($row->{revision_count}, 3, 'recent_changes revision count is correct.');
}

package MockPage;
sub revision_id { }
sub load        { }
sub store       { }
sub restore_revision { }
sub uri         {'correct_place_to_redirect_to'}

package main;
{
    my $redirected_to = 'nothing';
    no warnings qw(once redefine);
    local *Socialtext::Pages::current = sub { bless {}, 'MockPage' };
    local *Socialtext::RevisionPlugin::redirect = sub { $redirected_to = $_[1] };

    $hub->revision->revision_restore;    # note that this just uses cgi arg =(
    is $redirected_to, MockPage::uri(),
        'Socialtext::RevisionPlugin::revision_restore redirects to the current page URI.';
}

pass "done";
