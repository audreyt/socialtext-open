#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::More tests => 41;
use Test::Socialtext::Fatal;
use mocked 'Socialtext::Page';
use mocked 'Socialtext::Headers';
use mocked 'Socialtext::CGI';
use mocked 'Socialtext::SQL', ':test';
use mocked 'Socialtext::User';
use mocked 'Socialtext::Hub';

BEGIN {
    use_ok('Socialtext::Events');
}

my $insert_re = qr/^INSERT INTO event \( at, event_class, action, actor_id, person_id, page_id, page_workspace_id, signal_id, tag_name, context, group_id \) VALUES/;
my $insert_view_re = qr/^INSERT INTO view_event \( at, event_class, action, actor_id, person_id, page_id, page_workspace_id, signal_id, tag_name, context, group_id \) VALUES/;

my $user = Socialtext::User->new(
    user_id => 2345, 
    name => 'tiffany'
);
my $viewer = $user;
my @viewer_args = ($viewer->user_id) x 6;
my $ws = Socialtext::Workspace->new(
    workspace_id => 348798,
    name => 'forbao',
    title => 'O HAI',
);
my $hub = Socialtext::Hub->new(
    current_workspace => $ws,
    current_user => $user,
);
my $page = Socialtext::Page->new(
    id => 'example_page',
    name => 'Example Page!',
    revision_id => "abcd",
    revision_count => 56,
    hub => $hub,
);
is $page->id, 'example_page';
Socialtext::Pages->StoreMocked($page);

Creating_events: {

    Record_checks_required_params: {
        my %ev = (
            at          => 'whenevs',
            event_class => 'page',
            action      => 'view',
            actor       => 1,
            page        => 'hello_world',
            workspace   => 22,
        );

        foreach my $key (qw(event_class action actor page workspace)) {
            ok exception {
                local $ev{$key} = undef;
                Socialtext::Events->Record(\%ev);
            }, 'no event_class parameter';
            ok_no_more_sql();
        }

        $ev{event_class} = 'person';
        delete $ev{page};
        delete $ev{workspace};

        ok exception {
            Socialtext::Events->Record(\%ev);
        }, 'no person parameter';
        ok_no_more_sql();


        $ev{person} = 2;
        $ev{context} = "invalid json";

        ok exception {
            Socialtext::Events->Record(\%ev);
        }, 'invalid json';
        ok_no_more_sql();
    }


    Record_valid_view_event: {
        Socialtext::Events->Record({
            timestamp   => 'whenevs',
            action      => 'view',
            actor       => 1,
            page        => 'hello_world',
            workspace   => 22,
            event_class => 'page',
        });
        sql_ok(
            name => "Record valid event",
            sql => $insert_view_re,
            args => [ 'whenevs', 'page', 'view', 1, undef,
                      'hello_world', 22, (undef) x 4 ],
        );
        ok_no_more_sql();
    }

    Record_valid_edit_event: {
        Socialtext::Events->Record({
            timestamp   => 'whenevs',
            action      => 'edit',
            actor       => 1,
            page        => 'hello_world',
            workspace   => 22,
            event_class => 'page',
        });
        sql_ok(
            name => "Record valid event",
            sql => $insert_re,
            args => [ 'whenevs', 'page', 'edit', 1, undef,
                      'hello_world', 22, (undef) x 4 ],
        );
        ok_no_more_sql();
    }
    Record_page_object: {
        Socialtext::Events->Record( {
            action      => 'view',
            event_class => 'page',
            page        => $page
        } );
        sql_ok(
            name => "Record event with page object",
            sql => $insert_view_re,
            args => ['now', 'page', 'view', 2345, 
                     undef, 'example_page',  348798, undef, undef,
                     '{"revision_id":"abcd","edit_summary":"awesome","revision_count":"56"}',
                     undef],
        );
        ok_no_more_sql();
    }

    Record_event_specified_timestamp: {
        Socialtext::Events->Record( {
            at => 'yesterday',
            event_class => 'page',
            action => 'tag',
            actor => 4376,
            page => 'woot_woot',
            workspace => 832,
            context => '{"a":"b"}',
        } );
        sql_ok(
            name => 'Record event specified timestamp',
            sql => $insert_re,
            args => ['yesterday', 'page', 'tag', 4376, undef,
                     'woot_woot',  832, undef, undef, '{"a":"b"}', undef],
        );
        ok_no_more_sql();
    }

    Record_event_with_user_object: {
        Socialtext::Events->Record( {
            actor => Socialtext::User->new( user_id => 42 ),
            person => Socialtext::User->new( user_id => 123 ),
            at => 'yesterday',
            event_class => 'page',
            action => 'tag',
            page => 'yee_haw',
            workspace => 832111,
            context => '[{"c":"d"}]',
        } );
        sql_ok(
            name => 'Record event with user object',
            sql => $insert_re,
            args => ['yesterday', 'page', 'tag', 42, 123,
                     'yee_haw', 832111, undef, undef, '[{"c":"d"}]', undef],
        );
        ok_no_more_sql();
    }
}

blacklist_events: {
    Socialtext::Events->BlackList(
        { a => 1 },
    );
    my $event = {a => 1};
    is(Socialtext::Events->EventInBlackList($event), 1, 'Event in blacklist');
    $event = {a => 2};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Event with same key but different value not in blacklist');
    $event = {b => 2};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Event in no matching keys not in blacklist');
    Socialtext::Events->BlackList(
    );
    $event = {a => 1};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Reset clears blacklist');
    Socialtext::Events->BlackList(
        {
            a => 1,
            b => 'bob',
            c => 'Wild',
        }
    );
    $event = {a => 1};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Only one key means not in blacklist');
    $event = {a => 1, b => 'bob'};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Only two keys means not in blacklist');
    $event = {a => 1, c=> 'Senators', b => 'bob'};
    is(Socialtext::Events->EventInBlackList($event), 0, 'All keys, 2 matches, means not in blacklist');
    $event = {a => 1, c=> 'Wild', b => 'bob'};
    is(Socialtext::Events->EventInBlackList($event), 1, 'All the keys match so in the blacklist');
    Socialtext::Events->BlackList(
        {
            a => 1,
            b => 'backstrom',
            c => 'Wild',
        },
        {
            a => 1,
            b => 'leclaire',
            c => 'Senators',
        }
    );
    $event = {a => 1, b=> 'backstrom', c => 'Senators'};
    is(Socialtext::Events->EventInBlackList($event), 0, 'Match in multiple blacklist not found');
    $event = {a => 1, b=> 'leclaire', c => 'Senators'};
    is(Socialtext::Events->EventInBlackList($event), 1, 'Match found in multiple blacklist');
}

exit;
