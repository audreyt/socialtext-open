#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 32;
use Socialtext::Events;
use Socialtext::SQL;
use utf8;

fixtures( 'db' );
my $Hub = create_test_hub();

my $Eddie_email = "eddie$$\@devnull.socialtext.net";
my $Eddie = Socialtext::User->create(
    username => "eddie$$",
    email_address => $Eddie_email,
);
push @Test::Socialtext::Added_users, $Eddie->user_id; # for cleanup
my $Alice_email = "alice$$\@devnull.socialtext.net";
my $Alice = Socialtext::User->create(
    username => "alice$$",
    email_address => $Alice_email,
);
push @Test::Socialtext::Added_users, $Alice->user_id; # for cleanup
my $Bob_email = "bob$$\@devnull.socialtext.net";
my $Bob = Socialtext::User->create(
    username => "bob$$",
    email_address => $Bob_email,
);
push @Test::Socialtext::Added_users, $Bob->user_id; # for cleanup

$Hub->current_user($Eddie);
$Hub->current_workspace->add_user(user => $_) for ($Eddie, $Alice, $Bob);

my $page_name = "Some Page";

Two_user_edit_cancel: {
    is $Hub->current_user->user_id, $Eddie->user_id;
    my $page = $Hub->pages->new_from_name($page_name);
    $page->edit_rev();
    $page->append("New paragraph");
    $page->store();

    ok ! $page->edit_in_progress, "No edit started yet";

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });

    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });

    $Hub->current_user($Eddie);

    my $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Eddie_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Alice_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    $Hub->current_user($Eddie);
    $edit = $page->edit_in_progress;
    ok ! $edit, "The edit was cancelled";
}

# Test case with multiple editors
#
# alice start#1
# ? saved#2
# bob start#2
# eddie start#2
# eddie cancel#2
# alice cancel#1
#
# view rev#2 - should show bob's edit

More_complex: {
    is $Hub->current_user->user_id, $Eddie->user_id;
    my $page = $Hub->pages->new_from_name($page_name);
    ok $page->edit_rev(user => $Eddie);
    $page->append("New paragraph");
    $page->store(user => $Eddie);

    ok ! $page->edit_in_progress, "No edit started yet";

    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });

    $Hub->current_user($Eddie);
    my $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Alice_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    # Now create a new page revision, blowing away alice's edit
    $page->edit_rev(user => $Eddie);
    $page->append("New paragraph");
    $page->store(user => $Eddie);

    # Now there shouldn't be any open edit revisions we care about
    ok ! $page->edit_in_progress, "No edit started yet";

    # Now start some more edits
    $Hub->current_user($Bob);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });
    $Hub->current_user($Eddie);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });

    # Now eddie cancels
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Bob_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    # Now cancel Alice's old edit
    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    # Now we should just see Bob's edit he started a while ago
    $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Bob_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';
}


# another test case - same user start/cancel several times
Same_user_start_cancel_several_times: {
    $Hub->current_user($Eddie);
    is $Hub->current_user->user_id, $Eddie->user_id;
    my $page = $Hub->pages->new_from_name($page_name);
    $page->edit_rev(user => $Eddie);
    $page->append("New paragraph");
    $page->store(user => $Eddie);
    ok ! $page->edit_in_progress, "No edit started yet";

    # Alice is going to edit in a few different windows
    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_start',
        page => $page,
    });

    $Hub->current_user($Eddie);
    my $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Alice_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    $Hub->current_user($Eddie);
    $edit = $page->edit_in_progress;
    ok $edit, "An edit is started!";
    like $edit->{user_business_card}, qr/$Alice_email/;
    ok defined $edit->{minutes_ago}, 'has a minutes_ago';

    $Hub->current_user($Alice);
    Socialtext::Events->Record({
        event_class => 'page',
        action => 'edit_cancel',
        page => $page,
    });

    $Hub->current_user($Eddie);
    ok ! $page->edit_in_progress, "No edit started yet";
}

pass 'done';
