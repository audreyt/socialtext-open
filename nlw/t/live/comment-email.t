#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new->standard_query_validation;

__DATA__
=== Load page and look for comment button in a standard workspace
--- request_path: /admin/index.cgi?conversations
--- MATCH_WHOLE_PAGE
--- match
<table id="st-comment-button" class="st-page-action-button">
>Comment</a>

=== Load page to set current workspace and alter config
--- request_path: /admin/index.cgi
--- do: setWorkspaceConfig comment_by_email 1

=== Load page again to see if we are putting page name in URI as subject for mailto
--- request_path: /admin/index.cgi?conversations
--- MATCH_WHOLE_PAGE
--- nomatch
comment_popup
--- match
<a href="mailto:admin\@.*\?subject=Conversations" title="To\: admin\@.* \/ subject\: Conversations">Email To This Page<\/a>

=== Hit the settings page for blog Creation
--- query
action: blogs_create
--- match: Create A Blog

=== Create the Comment Blog
--- query
Button: Create
action: blogs_create
weblog_title: Comment blog
--- match
Blog: Comment blog
or post by email
first post in Comment blog.
