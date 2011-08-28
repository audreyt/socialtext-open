#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::More tests => 10;
use Test::Socialtext;
use Test::Socialtext::Fatal;
fixtures(qw(plugin));

my $hub = create_test_hub;
my $workspace1 = $hub->current_workspace;
my $workspace2 = create_test_workspace(user => $hub->current_user);

$workspace1->enable_plugin('prefsetter');
$workspace2->enable_plugin('prefsetter');
$workspace1->enable_plugin('other');
$workspace2->enable_plugin('other');

my $plugin = Socialtext::Pluggable::Plugin::Prefsetter->new;
$plugin->hub($hub);

Getter_setter: {
    $hub->current_workspace($workspace1);

    ok !exception {
        $plugin->set_workspace_prefs(
            number => 43,
            string => 'hi',
            ignored => [qw(some ref value)],
        );
    }, "set_workspace_prefs";

    is_deeply $plugin->get_workspace_prefs,
              { number => 43, string => 'hi' },
              'get_workspace_prefs';

    ok !exception {
        $plugin->set_workspace_prefs(
            number => 44,
            other => 'ho',
        );
    }, "set_workspace_prefs with a subset";

    is_deeply $plugin->get_workspace_prefs,
              { number => 44, string => 'hi', other => 'ho' },
              'get_workspace_prefs';

    ok !exception {
        $plugin->clear_workspace_prefs();
    }, "clear_workspace_prefs()";

    is_deeply $plugin->get_workspace_prefs, { },
              'clear_workspace_prefs';
}

Workspace_scoped: {
    $hub->current_workspace($workspace2);
    ok !exception { $plugin->set_workspace_prefs(number => 32) },
             "set_workspace_prefs(number => SCALAR)";
    is_deeply $plugin->get_workspace_prefs,
              { number => 32 },
              "prefs are workspace scoped";
}

No_workspace: {
    $hub->current_workspace(undef);

    ok exception { $plugin->get_workspace_prefs }, "workspace is required"
}

Plugin_scope: {
    my $other_plugin = Socialtext::Pluggable::Plugin::Other->new;
    $other_plugin->hub($hub);
    $hub->current_workspace($workspace1);

    is_deeply $other_plugin->get_workspace_prefs, {},
        "prefs are plugin scoped";
}

package Socialtext::Pluggable::Plugin::Prefsetter;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'workspace' }

package Socialtext::Pluggable::Plugin::Other;
use base 'Socialtext::Pluggable::Plugin';
sub scope { 'workspace' }
