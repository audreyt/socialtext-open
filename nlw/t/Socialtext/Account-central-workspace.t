#!/usr/bin/env perl

# there are some central workspace tests in
# 't/Socialtext/Gadgets/Container/Dashboard-central_workspace.t', this test
# will focus on passing a template workspace

use strict;
use warnings;

use Test::Socialtext tests => 6;
use Test::Differences 'eq_or_diff';
use Socialtext::User;
use Socialtext::String 'title_to_id';

BEGIN {
    use_ok('Socialtext::Account');
}
fixtures('db');

my $account = create_test_account_bypassing_factory();
ok !$account->central_workspace, 'account has no central workspace';

my $template = create_test_workspace(account=>$account);
my $user = create_test_user();

my $hub = new_hub($template->name, $user->username);

my $page_id = title_to_id($template->name."-another-page", 1);
my $page = $hub->pages->new_from_name($page_id);
$hub->pages->current->create(
    content => 'For Science',
    creator => $user,
    title => $page_id,
);
my @template_pages = sort map { $_->page_id } $hub->pages->all();

my $central = $account->create_central_workspace($template);
ok $account->central_workspace, 'central workspace created';
isa_ok $central, 'Socialtext::Workspace';
is $central->name, $account->name .'-central', 'workspace has correct name';

$hub->current_workspace($central);
my @central_pages = sort map { $_->page_id } $hub->pages->all();
eq_or_diff \@template_pages, \@central_pages, 'central page_ids match template';

exit;
