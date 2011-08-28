#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Test::Differences;
use Socialtext::Workspace;

fixtures('empty');
my $hub = new_hub('empty');

my %tz_prefs = (
    timezone => {
        date_display_format => 'mmm_d_yyyy',
        dst => 'auto-us',
        time_display_12_24 => '12',
        time_display_seconds => '0',
        timezone => '-0800',
    }
);

no_prefs: {
    my $workspace = create_test_workspace();
    $hub->current_workspace($workspace);
    my $user = create_test_user();
    my $prefs = $hub->preferences_object;

    my $global_prefs = $prefs->Global_user_prefs($user);
    my $wksp_prefs = $prefs->Workspace_user_prefs($user, $workspace);

    my $all = $prefs->_load_all_for_user($user);

    eq_or_diff $global_prefs, \%tz_prefs, 'global prefs are default';
    eq_or_diff $wksp_prefs, +{}, 'no workspace prefs set';
    eq_or_diff $all, $global_prefs, 'all prefs match global prefs';
}

store_prefs: {
    my $workspace = create_test_workspace();
    $hub->current_workspace($workspace);
    my $user = create_test_user();
    my $prefs = $hub->preferences_object;

    $prefs->store($user, 'workspaces_ui', {true=>1});
    my $wksp_prefs = $prefs->Workspace_user_prefs($user, $workspace);
    eq_or_diff $wksp_prefs, {workspaces_ui => {true=>1}}, 'stored ws prefs';

    $prefs->store($user, 'timezone', {true=>1});
    my $global_prefs = $prefs->Global_user_prefs($user);
    eq_or_diff $global_prefs, {timezone => {true=>1}}, 'stored global prefs';

    my $all = $prefs->_load_all_for_user($user);
    eq_or_diff $all,
        { workspaces_ui => {true=>1}, timezone => {true=>1} },
        'all settings are correct';
}

ignore_prefs_for_noworkspace: {
    my $workspace = Socialtext::NoWorkspace->new();
    $hub->current_workspace($workspace);
    my $user = create_test_user();
    my $prefs = $hub->preferences_object;

    $prefs->store($user, 'workspaces_ui', {true=>1});
    my $wksp_prefs = $prefs->Workspace_user_prefs($user, $workspace);
    eq_or_diff $wksp_prefs, {}, 'ignored noworkspace prefs';
}

# we won't ever run into this if we use the 'store' convention.
global_overrides_workspace: {
    my $workspace = create_test_workspace();
    $hub->current_workspace($workspace);
    my $user = create_test_user();
    my $prefs = $hub->preferences_object;

    $prefs->Store_workspace_user_prefs(
        $user, $workspace, {foo => {true=>0}, bar => {true=>1}});
    $prefs->Store_global_user_prefs(
        $user, {foo => {true=>1}, baz => {true=>1}});

    my $all = $prefs->_load_all_for_user($user);
    eq_or_diff $all,
        { foo => {true=>1}, bar => {true=>1}, baz => {true=>1}, %tz_prefs },
        'global settings override workspace settings';
}

done_testing;
exit;
