#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin', 'foobar'];
use Socialtext::User;

my $tester = Test::Live->new;
Socialtext::User->create(
    username => 'noworkspaces@socialtext.com',
    email_address => 'noworkspaces@socialtext.com',
    password => 'password',
    require_password => 1,
);
$tester->dont_log_in(1);
$tester->standard_query_validation;


# For another user pref's test (that actually asserts that the setting made a
# difference), see t/live/workspace-settings.t

__DATA__
=== Attempt to access a page that requires login
--- query
page_name: conversations
action: display
--- match: Log in to Socialtext

=== Bungle the login
--- post
username: mehmehmeh@icannottype.com
password: burrrrr
--- match: please try again

=== Log in, which should redirect
--- post
username: devnull1@socialtext.com
password: d3vnu11l
--- match: Group-forming metrics

=== Go to email_notify prefs page:
--- query
preferences_class_id: email_notify
action: preferences_settings
--- match: How often would you like to receive email updates?

=== Turn off email updates
--- form: 2
--- post
Button: Button
email_notify__notify_frequency: 0
--- YAGNI: Button=Save&action=preferences_settings&preferences_class_id=email_notify&email_notify__notify_frequency=0&email_notify__sort_order=chrono&email_notify__links_only=expanded
--- match
Preferences saved
selected="selected"\s*>Never

=== Log out
--- request_path: /nlw/submit/logout
--- match: Log in to Socialtext

=== Try to visit foobar
--- request_path: /foobar/index.cgi?conversations
--- match: Log in to Socialtext

=== Try to Log in with spaces and capitalization (as powerless user)
--- post
username: '   devNull2@sociaLText.CoM  '
password: '   d3vnu11l   '
--- match: Group-forming metrics

=== Try to perform an action with insufficient rights
--- request_path: /foobar/index.cgi?action=users_invite
--- match
<title>Dashboard

=== Log out again
--- request_path: /nlw/submit/logout
--- match: Log in to Socialtext

=== Visit /nlw/login
--- request_path: /nlw/login.html
--- match: Log in to Socialtext

=== Try to Log in again as a user w/o workspaces
--- post
username: noworkspaces@socialtext.com
password: password
--- match: Socialtext Documentation
