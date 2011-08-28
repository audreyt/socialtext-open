#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 12;
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

Getter_setter: {
    ok !exception {
        $plugin->set_user_prefs(
            number => 43,
            string => 'hi',
            'ref' => ['ignored'],
        );
    }, "set_user_prefs";

    is_deeply $plugin->get_user_prefs,
              { number => 43, string => 'hi' },
              'get_user_prefs';

    ok !exception {
        $plugin->set_user_prefs(
            number => 44,
            other => 'ho',
        );
    }, "set_user_prefs with a subset";

    is_deeply $plugin->get_user_prefs,
              { number => 44, string => 'hi', other => 'ho' },
              'get_user_prefs';

    ok !exception {
        $plugin->clear_user_prefs();
    }, "clear_user_prefs";

    is_deeply $plugin->get_user_prefs, {}, 'get_user_prefs after clear';
}

User_scoped: {
    ok !exception { $plugin->set_user_prefs(number => 38) },
             "set_user_prefs(number => SCALAR)";
    $hub->current_user($user2);
    ok !exception { $plugin->set_user_prefs(number => 32) },
             "set_user_prefs(number => SCALAR)";
    is_deeply $plugin->get_user_prefs,
              { number => 32 },
              "prefs are user scoped";
    $hub->current_user($user1);
    ok !exception { $plugin->set_user_prefs(number => 38) },
             "set_user_prefs(number => SCALAR)";
}

No_user: {
    $hub->current_user(undef);

    ok exception { $plugin->get_user_prefs }, "user is required"
}

Plugin_scoped: {
    # depends on the setup in "User_scoped" above
    my $other_plugin = Socialtext::Pluggable::Plugin::Other->new;
    $other_plugin->hub($hub);
    $hub->current_user($user1);

    is_deeply $other_plugin->get_user_prefs, {},
        "prefs are plugin scoped";
}

package Socialtext::Pluggable::Plugin::Prefsetter;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'user' }

package Socialtext::Pluggable::Plugin::Other;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'user' }
