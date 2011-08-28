#!perl
# @COPYRIGHT@
use warnings FATAL => 'all';
use strict;
use mocked 'Apache::Cookie';
use mocked 'Socialtext::Events', 'event_ok', 'is_event_count';
use Test::More tests => 31;
use URI::Escape qw/uri_escape/;
use Socialtext::JSON qw/decode_json/;
use Socialtext::HTTP qw/:codes/;
use t::RestTestTools qw/do_get_json do_post_form do_post_json is_status/;

use_ok 'Socialtext::Rest::Events';

our $actor;

sub test (&) {
    $actor = t::RestTestTools->default_actor();
    my $code = shift;
    eval { $code->() };
    my $err = $@;
    t::RestTestTools->reset_actor();
    die $err if $err;
}

Empty_JSON_GET: test {
    my ($rest, $result) = do_get_json();

    is_status $rest, '200 OK', "request succeeded";
    my $events = decode_json($result);
    ok($events, "decoded the result");
    is_deeply $events, [], "empty result";
    is_deeply \@Socialtext::Events::GetArgs, [[ 
        $actor,
        count => 25 
    ]], "expected parameters passed";
};

JSON_GET_an_item: test {
    my %args = ( 
        after => '2008-06-25 11:39:21.509539-07', 
        before => '2008-06-23T00:00:00Z', 
        event_class => 'PAGE',
        action => 'tAg_Add',
        'actor.id' => 156,
        'page.id' => 'quick_start',
        'page.workspace_name' => 'foobar',
        'tag_name' => 'Some Tag',
        count => 42,
        offset => 25,
    );
    local @Socialtext::Events::Events
        = [ { item => 'first', minutes => 3, at => 9 } ];
    my ($rest, $result) = do_get_json(%args);

    is_status $rest, '200 OK', "request succeeded";
    my $events = decode_json($result);
    ok($events, "decoded the result");
    my $html = delete $events->[0]{html};
    ok $html, 'html version of event is included';
    is_deeply $events, [ { item => 'first', minutes => 3, at => 9 } ],
        "mock result returned";
    is_deeply \@Socialtext::Events::GetArgs, [[ 
        $actor,
        count => 42,
        offset => 25,
        before => '2008-06-23T00:00:00Z',
        after => '2008-06-25 11:39:21.509539-07', 
        event_class => 'page',
        action => 'tag_add',
        tag_name => 'Some Tag',
        actor_id => 156,
        page_workspace_id => 1,
        page_id => 'quick_start',
    ]], "expected parameters passed";
};

GET_without_authorized_user: test {
    t::RestTestTools->set_actor(Socialtext::User->new(is_guest => 1));
    my ($rest, $result) = do_get_json();

    is_status $rest, HTTP_401_Unauthorized, "request denied";
};

POSTing_an_event: test {
    my ($rest, $result) = do_post_form(
        event_class => 'page',
        action => 'edit_begin',
        'actor.id' => 1,
        'page.id' => 'formattingtest',
        'page.workspace_name' => 'foobar',
        context => '{"page_rev":"123456789"}',
    );

    like $result, qr/success/, "successful operation";
    is_status $rest, HTTP_201_Created, "created";

    is_event_count(1);
    event_ok(
        event_class => 'page',
        action => 'edit_begin',
        page => 'formattingtest',
        workspace => 1,
        context => {"page_rev"=>"123456789"},
    );
};

POSTing_without_actor: test {
    t::RestTestTools->set_actor(
        Socialtext::User->new(
            user_id => 98,
            username => 'auto-actor@devnull',
            email => 'auto-actor@example.com',
            first_name => 'Auto',
            last_name => 'Actor',
            is_guest => 0
        )
    );

    my ($rest, $result) = do_post_json({
        event_class => 'page',
        action => 'edit_cancel',
        'page' => {id => 'qvick_stvrt', workspace_name => 'foobar'},
        context => {page_rev => "187654321"},
    });

    like $result, qr/success/, "successful operation";
    is_status $rest, HTTP_201_Created, "created";

    is_event_count(1);
    event_ok(
        actor => 98,
        event_class => 'page',
        action => 'edit_cancel',
        page => 'qvick_stvrt',
        workspace => 1,
        context => {"page_rev"=>"187654321"},
    );
};

POSTing_without_authorization: test {
    $actor = t::RestTestTools->set_actor(Socialtext::User->new(is_guest => 1));
    my ($rest, $result) = do_post_form(
        event_class => 'page',
        action => 'edit_begin',
        'actor.id' => 1,
        'page.id' => 'formattingtest',
        'page.workspace_name' => 'foobar',
        context => '{"page_rev":"123456789"}',
    );

    like $result, qr/not authorized/i, "denied";
    is_status $rest, HTTP_401_Unauthorized, "request denied";
    is_event_count(0);
};

exit;
