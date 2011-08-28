#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
Test::Live->new->standard_query_validation;

__DATA__
=== workspaces_settings_features
--- query
action: workspaces_settings_features
--- match
<input type="radio" name="enable_unplugged"

=== Turn off unplugged
--- form: 2
--- post
Button: Button
incoming_email_placement: bottom
email_notify_is_enabled: 0
enable_unplugged: 0
--- match
   <input type="radio" name="enable_unplugged"
    checked
    value="0" />
   Socialtext Unplugged disabled<br/>

=== Turn on unplugged
--- form: 2
--- post
Button: Button
incoming_email_placement: bottom
email_notify_is_enabled: 0
enable_unplugged: 1
--- match
   <input type="radio" name="enable_unplugged"
    checked
    value="1" />
   Socialtext Unplugged enabled<br/>
