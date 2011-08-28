#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Encode 'decode_utf8';

use Test::Live;
use Socialtext::Jobs;
use Socialtext::System qw/shell_run/;


my $tl = Test::Live->new(dont_log_in => 1);

{ # Create and index a page with a Unicode name, for a test below.
    my $hub = Test::Socialtext::Environment->instance->hub_for_workspace(
        'public');
    Socialtext::Jobs->clear_jobs();
    my $page = $hub->pages->new_from_name(decode_utf8('繁體中'));
    $page->title(decode_utf8('繁體中'));
    $page->content('cows love cancer');
    $page->store( user => Socialtext::User->Guest );
    shell_run("$ENV{ST_CURRENT}/nlw/bin/ceqlotron -o -f");
}

$tl->standard_query_validation;

__DATA__

=== Go to syndication preferences
--- request_path: /public/index.cgi?action=preferences_settings;preferences_class_id=syndicate
--- match
How many posts

=== Set the syndication_depth preference
--- form: 2
--- post
Button: Button
syndicate__syndication_depth: 50
--- match
Preferences saved

=== Hit public for standard RSS
--- request_path: /feed/workspace/public
--- query
category: Recent Changes
--- match
<rss version="2.0" xmlns:blogChannel="http://backend.userland.com/blogChannelModule">
<channel>
<title><!\[CDATA\[Public Wiki: Recent Changes\]\]></title>
<link>http://.*/public/index.cgi\?action=blog_display;category=Recent%20Changes</link>

=== Hit old-style URL
--- request_path: /public/index.cgi
--- query
action: rss20
category: Recent Changes
--- match
<rss version="2.0" xmlns:blogChannel="http://backend.userland.com/blogChannelModule">
<channel>
<title><!\[CDATA\[Public Wiki: Recent Changes\]\]></title>
<link>http://.*/public/index.cgi\?action=blog_display;category=Recent%20Changes</link>

=== Log in and request public feed
--- do: log_in
--- request_path: /feed/workspace/public
--- query
category: Recent Changes
--- match
<rss version="2.0" xmlns:blogChannel="http://backend.userland.com/blogChannelModule">
<channel>
<title><!\[CDATA\[Public Wiki: Recent Changes\]\]></title>
<link>http://.*/public/index.cgi\?action=blog_display;category=Recent%20Changes</link>

=== Hit old-style URL in public workspace
--- request_path: /public/index.cgi
--- query
action: rss20
category: Recent Changes
--- match
<rss version="2.0" xmlns:blogChannel="http://backend.userland.com/blogChannelModule">
<channel>
<title><!\[CDATA\[Public Wiki: Recent Changes\]\]></title>
<link>http://.*/public/index.cgi\?action=blog_display;category=Recent%20Changes</link>

=== Check for correct linking in dashed workspace
--- request_path: /feed/workspace/auth-to-edit
--- match
href="http://.*(?<!/auth-to-edit/)/auth-to-edit/index.cgi\?formattingtest

=== Check utf8 handling Atom
--- request_path: /feed/workspace/public?page=babel;type=Atom
--- SKIP_DOUBLE_ESCAPE_SANITY_CHECK
--- match
繁體中文版 \(Traditional Chinese\)
1. 那時，天下人的口音言語，都是一樣。

=== Check utf8 handling RSS
--- request_path: /feed/workspace/public?page=babel
--- match
繁體中文版 \(Traditional Chinese\)
1. 那時，天下人的口音言語，都是一樣。

=== Check for per page links
--- request_path: /public/index.cgi?public wiki
--- MATCH_WHOLE_PAGE
--- match
title="Public Wiki - Public Wiki RSS"
href="/feed/workspace/public\?page=public_wiki" />
title="Public Wiki - Public Wiki Atom"
href="/feed/workspace/public\?page=public_wiki;type=Atom" />

=== Check for proper utf8 weirdness handling
--- request_path: /feed/workspace/public?type=Atom
--- MATCH_WHOLE_PAGE
--- SKIP_DOUBLE_ESCAPE_SANITY_CHECK
--- match
This quick tour will help you get acquainted with

=== Handle pages with Unicode names
--- request_path: /noauth/feed/workspace/public?search_term=cancer;scope=_
--- match
<channel>

