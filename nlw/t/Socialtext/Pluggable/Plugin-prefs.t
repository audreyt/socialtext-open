#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 5;
use Test::Socialtext;
use Socialtext::Account;
use Socialtext::User;
use Test::Socialtext::Fatal;
fixtures(qw(plugin));

my $hub = create_test_hub;
my $user1 = create_test_user();
my $user2 = create_test_user();
$hub->current_user($user1);

my $plugin = Socialtext::Pluggable::Plugin::Prefsetter->new;
$plugin->hub($hub);

$plugin->clear_plugin_prefs;

# Get/Set
{
    ok !exception {
        $plugin->set_plugin_prefs(
            number => 43,
            string => 'hi',
            array => ['some','crap'], # will be ignored
            object => $user1, # ditto
        );
    }, "set_plugin_prefs";

    is_deeply $plugin->get_plugin_prefs,
              { number => 43, string => 'hi' },
              'get_plugin_prefs';

    ok !exception {
        $plugin->set_plugin_prefs(
            number => 44,
            other => 'ho',
            array => ['more','crap'],
        );
    }, "set_plugin_prefs with a subset";

    is_deeply $plugin->get_plugin_prefs,
              { number => 44, string => 'hi', other => 'ho' },
              'get_plugin_prefs';

    $plugin->clear_plugin_prefs;
    is_deeply $plugin->get_plugin_prefs, {},
              'get_plugin_prefs after clear';
}

package Socialtext::Pluggable::Plugin::Prefsetter;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'user' }
