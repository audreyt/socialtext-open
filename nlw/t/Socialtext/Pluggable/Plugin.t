#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 35;
use mocked 'Socialtext::CGI';
use mocked 'Socialtext::SQL';
use mocked 'Socialtext::Page';
use mocked 'Socialtext::Authz';
use mocked 'Socialtext::AppConfig';
use mocked 'Socialtext::User';
use mocked 'Socialtext::Hub';

use_ok 'Socialtext::Pluggable::Plugin';
use_ok 'Socialtext::Pluggable::Adapter';

my $plug = Socialtext::Pluggable::Plugin->new;
my $hub = Socialtext::Hub->new;
$plug->hub($hub);

# Config
$Socialtext::AppConfig::CODE_BASE = 't/share';
$Socialtext::AppConfig::SCRIPT_NAME = '/index.cgi';
$plug->hub->current_workspace->{uri} = 'http://hostname/magic';
$plug->hub->current_workspace->{name} = 'current';
is $plug->uri, 'http://hostname/magic/index.cgi', 'uri';
is $plug->code_base, $Socialtext::AppConfig::CODE_BASE, 'code_base';

# CGI
no warnings 'once';
$Socialtext::CGI::QUERY = {a => 1, b => 2};
is $plug->query_string, 'a=1;b=2', 'query_string';
is $plug->query->param('a'), 1, 'query 1';
is $plug->query->param('b'), 2, 'query 2';

$hub->rest->{_content} = 'content';
is $plug->getContent, 'content', 'getContent';
$hub->rest->{_contentprefs} = { content => 'prefs' };
is_deeply $plug->getContentPrefs, { content => 'prefs' }, 'getContentPrefs';

# User stuff
$hub->{current_user} = Socialtext::User->new(username => 'billy');
is_deeply $plug->user, {username => 'billy'}, 'user';
is $plug->username, 'billy', 'username';
is $plug->best_full_name('billy'), 'Mocked First Mocked Last', 'best_full_name';

# Headers
$plug->header_out('Content_Type' => 'text/html');
my %header_out = $plug->header_out;
is $header_out{Content_Type}, 'text/html', 'header_out';
$hub->rest->{headers_in} = { Accept => 'text/html' };
is $plug->header_in('Accept'), 'text/html', 'header_in';
is_deeply {$plug->header_in}, {Accept=>'text/html'}, 'header_in';

# Cache stuff
$plug->cache_value(key => 'a', value => 1);
is $plug->value_from_cache('a'), 1, 'can retrieve cache value';

# Workspace
isa_ok $plug->current_workspace, 'Socialtext::Workspace', 'current_workspace';
is $plug->current_workspace->name, 'current', 'current_workspace';

$plug->current_page->{type} = 'spreadsheet'; # hack the mock obj
is $plug->current_page_rest_uri, '/data/workspaces/current/sheets/welcome';
$plug->current_page->{type} = 'page'; # hack the mock obj back to a page
is $plug->current_page_rest_uri, '/data/workspaces/current/pages/welcome';


# Plugin functions
my %plugins = map { $_ => 1 } $plug->plugins;
ok $plugins{testplugin}, 'TestPlugin plugin exists';
is $plug->plugin_dir('mocked'), "$Socialtext::AppConfig::CODE_BASE/plugin/mocked",
   'Mocked directory is correct';

# Page stuff
my $page = $plug->get_page(workspace_name => 'admin', page_name => 'Start Here');
ok defined $page, 'Page object found';
is $page->title, 'Mock page title', 'Fetched page from workspace';
$page = $plug->get_page(workspace_name => 'bad_workspace', page_name => 'Start Here');
ok ! defined $page, 'No page object on invalid workspace';
my $page_creator = $plug->created_by(workspace_name => 'admin', page_name => 'Start Here');
ok defined $page_creator, 'Page creator found';
is $page_creator->username, 'mocked_user', 'Proper creator retrieved';
$page_creator = $plug->created_by(workspace_name => 'bad_workspace', page_name => 'Start Here');
ok ! defined $page_creator, 'Invalid page returns undef creator';
my $page_created_at = $plug->created_at(workspace_name => 'admin', page_name => 'Start Here');
ok $page_created_at =~ /\w\w\w \d\d? \d\d?:\d\d[ap]m/, 'Create date retrieved';
$page_created_at = $plug->created_at(workspace_name => 'bad_workspace', page_name => 'Start Here');
ok ! defined $page_created_at, 'Invalid page returns undef create time';

# Tags
my @tags = $plug->tags_for_page(workspace_name => 'admin', page_name => 'Start Here');
is scalar(@tags), 1, 'Tag count is right';

# Tags
@tags = $plug->tags_for_page(workspace_name => 'admin', page_name => 'Start Here');
is scalar(@tags), 1, 'Tag count is right';
is $tags[0], 'mock_category', 'first tag is right';
@tags = $plug->tags_for_page(workspace_name => 'bad_workspace', page_name => 'Start Here');
is scalar(@tags), 0, 'Non-existant page has an empty tag list';

# Page Caching
# This one is kind of funky. When we fetch a page we cache it. So we add
# tags to the page we fetched but do not save the page. Then we ask for
# the tags for the page. If the page caching works, the call to get tags
# should use the cached page which will have our new tags 
$page = $plug->get_page(workspace_name => 'admin', page_name => 'Start Here');
@tags = $plug->tags_for_page(workspace_name => 'admin', page_name => 'Start Here');
my $before_count = scalar(@tags);
$page->add_tags('t1', 't2');
@tags = $plug->tags_for_page(workspace_name => 'admin', page_name => 'Start Here');
ok scalar(@tags) > $before_count, 'Plugin used cached page';
