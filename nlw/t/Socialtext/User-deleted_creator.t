#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Socialtext;
use Socialtext::SQL qw/sql_execute/;

use Socialtext::User;
use Socialtext::Group;
use Socialtext::Workspace;

fixtures('db');

my $user = create_test_user();
my $user_id = $user->user_id;

my $group = create_test_group(user=>$user);
my $group_id = $group->group_id;

my $ws = create_test_workspace(user=>$user);
my $ws_id = $ws->workspace_id;

sql_execute(
    'UPDATE all_users SET is_deleted = true WHERE user_id = ?', $user_id);

$user = Socialtext::User->new(user_id=>$user_id);
ok $user, 'found a user';
ok $user->missing, '... marked as "missing"';
isa_ok $user->homunculus, 'Socialtext::User::Deleted', '... homunculus';

$group = Socialtext::Group->GetGroup({group_id=>$group_id});
$user = $group->creator;
ok $user, 'found group creator';
ok $user->missing, '... marked as "missing"';
isa_ok $user->homunculus, 'Socialtext::User::Deleted', '... homunculus';

$ws = Socialtext::Workspace->new(workspace_id=>$ws_id);
$user = $ws->creator;
ok $user, 'found workspace creator';
ok $user->missing, '... marked as "missing"';
isa_ok $user->homunculus, 'Socialtext::User::Deleted', '... homunculus';

done_testing;
