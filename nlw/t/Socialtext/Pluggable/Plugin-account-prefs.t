#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 9;
use Test::Socialtext;
use Test::Socialtext::Fatal;
fixtures(qw(empty plugin));

my $hub = create_test_hub;
my $account1 = create_test_account;
my $account2 = create_test_account;

$account1->enable_plugin('prefsetter');
$account2->enable_plugin('prefsetter');
$account1->enable_plugin('other');
$account2->enable_plugin('other');

my $plugin = Socialtext::Pluggable::Plugin::Prefsetter->new;
$plugin->hub($hub);

Getter_setter: {

    ok !exception {
        $plugin->set_account_prefs(
            account => $account1,
            number => 43,
            string => 'hi',
            ignored => [qw(some ref value)],
        );
    }, "set_account_prefs";

    is_deeply $plugin->get_account_prefs(account => $account1),
              { number => 43, string => 'hi' },
              'get_account_prefs';

    ok !exception {
        $plugin->set_account_prefs(
            account => $account1,
            number => 44,
            other => 'ho',
        );
    }, "set_account_prefs with a subset";

    is_deeply $plugin->get_account_prefs(account => $account1),
              { number => 44, string => 'hi', other => 'ho' },
              'get_account_prefs';

    ok !exception {
        $plugin->clear_account_prefs(account => $account1);
    }, "clear_account_prefs()";

    is_deeply $plugin->get_account_prefs(account => $account1), { },
              'clear_account_prefs';
}

Account_scoped: {
    ok !exception { $plugin->set_account_prefs(account => $account2, number => 32) },
             "set_account_prefs(number => SCALAR)";
    is_deeply $plugin->get_account_prefs(account => $account2),
              { number => 32 },
              "prefs are account scoped";
}
 
Plugin_scope: {
    my $other_plugin = Socialtext::Pluggable::Plugin::Other->new;
    $other_plugin->hub($hub);

    is_deeply $other_plugin->get_account_prefs(account => $account1), {},
        "prefs are plugin scoped";
}

package Socialtext::Pluggable::Plugin::Prefsetter;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'account' }

package Socialtext::Pluggable::Plugin::Other;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'account' }
