#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 8;

use Data::Dumper;
use mocked 'Socialtext::CGI';
use mocked 'Socialtext::Events', qw/event_ok is_event_count/;
use mocked 'Socialtext::Page';
use mocked 'Socialtext::Formatter';
use mocked 'Socialtext::Formatter::Viewer';
use Socialtext::Headers;
use mocked 'Apache::Cookie';
use mocked 'Socialtext::Hub';

BEGIN { use_ok 'Socialtext::DisplayPlugin' }

my $hub = Socialtext::Hub->new;
my $page = Socialtext::Page->new(name => 'special_sauce', id => 'special_sauce');
$hub->pages->current($page);

no warnings 'redefine';
local *Socialtext::DisplayPlugin::_render_display = sub { "" };

View_existing_page: {
    my $dp = setup_plugin();
    $dp->display();

    is_event_count(1);
    event_ok(
        event_class => 'page', 
        action => 'view', 
        page => {
            id => 'special_sauce',
            name => 'special_sauce',
            tags => [],
        }
    );
}

Preview_no_event: {
    my $dp = setup_plugin(wiki_text => '');
    $dp->preview();
    is_event_count(0);
}

New_page: { 
    local *Socialtext::Pages::page_exists_in_workspace = sub { 0 };
    my $dp = setup_plugin();
    $dp->display();
    is_event_count(0);
}

View_untitled_page: { 
    my $untitled = Socialtext::Page->new(name => 'untitled_page', id => 'untitled_page');
    $hub->pages->current($untitled);
    my $dp = setup_plugin();
    $dp->display();
    is_event_count(0);
}

exit;

sub setup_plugin {
    my $cgi = Socialtext::Display::CGI->new(
        page_type => 'wiki',
        uri => 'mock_page',
        page_title => 'Mock Page',
        @_
    );
    my $dp = Socialtext::DisplayPlugin->new(
        hub => $hub,
        cgi => $cgi
    );
    return $dp;
}
