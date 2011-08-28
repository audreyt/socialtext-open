#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Data::Dumper;
use mocked 'Socialtext::CGI';
use mocked 'Socialtext::Events', qw/event_ok/;
use Socialtext::Attachments;
use Test::Socialtext tests => 10;

fixtures(qw( db ));

BEGIN { use_ok 'Socialtext::EditPlugin' }

my $hub = create_test_hub();

Edit_save_event: {
    my $ep = setup_plugin();
    ok($ep, "Created an EditPlugin");
    $ep->edit_content();
    event_ok(
        event_class => 'page',
        action => 'edit_save',
    );
}

Edit_contention: {
    no warnings 'redefine';
    local *Socialtext::EditPlugin::_there_is_an_edit_contention = sub { 1 };
    local *Socialtext::EditPlugin::_edit_contention_screen = sub { "" };
    my $ep = setup_plugin();
    ok($ep, "Created an EditPlugin");
    $ep->edit_content();
    event_ok(
        event_class => 'page',
        action => 'edit_contention',
    );
}

Edit_save: {
    my $ep = setup_plugin(
        original_page_id => 7,
        header => '',
    );
    ok($ep, "Created an EditPlugin");
    $ep->edit_save();
    event_ok(
        event_class => 'page',
        action => 'edit_save',
    );
}

exit;

sub setup_plugin {
    my $cgi = Socialtext::Edit::CGI->new(
        subject => 'Crazy New Page',
        page_name => 'crazy_new_page',
        page_body => 'Crazy content',
        @_,
    );
    my $ep = Socialtext::EditPlugin->new(
        hub => $hub,
        cgi => $cgi
    );
    return $ep;
}
