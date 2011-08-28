#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
fixtures(qw( empty ));

my $hub = new_hub('empty');

my $p2 = Socialtext::User->create(
    username => "user2-$$",
    email_address => "2-$$\@devnull.socialtext.net",
);
$hub->current_user($p2);
my $prefs = $hub->user_preferences->preferences;
$prefs->timezone->value('+0200');


my $p5 = Socialtext::User->create(
    username => "user5-$$",
    email_address => "5-$$\@devnull.socialtext.net",
);
$hub->current_user($p5);
$prefs = $hub->user_preferences->preferences;
$prefs->timezone->value('-0500');

# Get prefs for p2
$hub->current_user($p2);
my $p2_prefs = $hub->preferences_object;
is $p2_prefs->timezone->value, '+0200', 'Timezone is correct for p2 user';

# Get prefs for p5
$hub->current_user($p5);
my $p5_prefs = $hub->preferences_object;
is $p5_prefs->timezone->value, '-0500', 'Timezone is correct for p5 user';

# should be different

