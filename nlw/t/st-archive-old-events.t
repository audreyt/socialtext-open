#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext;
use Test::More tests => 3;
use Socialtext::Events;
use Socialtext::SQL qw(:exec :time);
use Socialtext::System qw(shell_run);
use Socialtext::Account;
use Socialtext::User;

fixtures(qw(db));

sql_execute('DELETE FROM event_archive');

# Create test events

my $date = Socialtext::Date->now;
my $test_days = 5 * 7; # Add 5 weeks to test 4 weeks
my $interval = '4 weeks';

my $hub = create_test_hub;
my $user_id = $hub->current_user->user_id;
my $workspace_id = $hub->current_workspace->workspace_id;

my $page;
$page = Socialtext::Page->new( hub => $hub )->create(
    title   => 'new page',
    content => 'First Paragraph',
    creator => $hub->current_user,
);

for (1 .. $test_days) {
    my $datestr = sql_format_timestamptz($date);
    Socialtext::Events->Record({
        timestamp   => $datestr,
        action      => 'edit',
        actor       => $user_id,
        page        => $page->id,
        workspace   => $workspace_id,
        event_class => 'page',
    });
    $date->subtract( days => 1 );
}

my $before = sql_singlevalue(q{
    SELECT COUNT(*)
      FROM event
     WHERE at < 'today'::timestamptz - ?::interval
}, $interval);
isnt $before, 0, "Events populated properly";

shell_run "st-archive-old-events '4 weeks'";

my $archived = sql_singlevalue(q{
    SELECT COUNT(*) FROM event_archive
});
is $archived, $before, "Old events were archived";

my $after = sql_singlevalue(q{
    SELECT COUNT(*)
      FROM event
     WHERE at < 'today'::timestamptz - ?::interval
}, $interval);
is $after, 0, "Old events were deleted from the event table";
