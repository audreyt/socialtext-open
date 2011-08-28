#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext;
fixtures(qw( empty ));

delimiters('===', '+++');
plan tests => 1 * blocks;

my $hub = new_hub('empty');

run_is object => 'html';

# XXX => Test::Socialtext as a general NLW filter*
sub call_method {
    my $obj = shift;
    my $method = filter_arguments;
    $obj->hub($hub); # * if we generalize this, where should $hub come from?
    $obj->$method;
}

__DATA__
=== Test formatting of a pulldown preference
+++ object yaml call_method=pulldown
--- !perl/Socialtext::Preference
choices:
  - 0
  - Never
  - 1
  - Every Minute
  - 5
  - Every 5 Minutes
  - 15
  - Every 15 Minutes
  - 60
  - Every Hour
  - 360
  - Every 6 Hours
  - 1440
  - Every Day
  - 4320
  - Every 3 Days
  - 10080
  - Every Week
default: 1440
handler: notify_frequency_handler
id: notify_frequency
name: Notify Frequency
owner_id: email_notify
query: How often would you like to receive email updates?
type: pulldown
value: 360
+++ html
<select name="email_notify__notify_frequency">
      <option value="0">Never</option>
      <option value="1">Every Minute</option>
      <option value="5">Every 5 Minutes</option>
      <option value="15">Every 15 Minutes</option>
      <option value="60">Every Hour</option>
      <option value="360" selected="selected">Every 6 Hours</option>
      <option value="1440">Every Day</option>
      <option value="4320">Every 3 Days</option>
      <option value="10080">Every Week</option>
  </select>


