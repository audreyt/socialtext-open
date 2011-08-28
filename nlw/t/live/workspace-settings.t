#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new->standard_query_validation;

__DATA__
=== workspaces_settings_appearance
--- query
action: workspaces_settings_appearance
--- match
<input type="text" name="title" value="Admin Wiki" size="50" />

=== save changes
--- form: 2
--- post
Button: Button
title: udmin spel wiki
logo_type: uri
logo_uri: 'http://www.example.com/eg.gif'
--- match
<div class="workspace-entry-header">Workspace Title</div>
<input type="text" name="title" value="udmin spel wiki" size="50" />
<div class="workspace-entry-header">Workspace Logo Image</div>
<input type="radio" checked="checked" name="logo_type" value="uri" /> <input type="text" name="logo_uri" value="http://www.example.com/eg.gif" size="30" />

=== workspaces_settings_features
--- query
action: workspaces_settings_features
--- match
<input type="radio" name="incoming_email_placement"
<input type="radio" name="enable_unplugged"

=== save changes
--- form: 2
--- post
Button: Button
incoming_email_placement: bottom
email_notify_is_enabled: 0
enable_unplugged: 0
--- match
<div class="workspace-entry-header">Workspace Email Receive Setting</div>
   <input type="radio" name="incoming_email_placement"
    checked
    value="bottom" />
    Bottom of page<br/>
<div class="workspace-entry-header">Workspace Email Notify Setting</div>
   <input type="radio" name="email_notify_is_enabled"
    checked
    value="0" />
   No<br/>

=== workspaces_settings_appearance - logo file
--- query
action: workspaces_settings_appearance
--- match
<input type="text" name="title"

=== save changes - logo file
--- do: chdir t/live
--- form: 2
--- post
Button: Button
logo_type: file
logo_file: 'C:\Documents\ and\ Settings\new-file.jpg'
--- match
Changes saved

