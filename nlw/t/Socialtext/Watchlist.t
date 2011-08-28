#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 12;
fixtures(qw( empty ));

use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::SQL qw/:exec/;

BEGIN { use_ok('Socialtext::Watchlist') }
sql_execute('DELETE FROM "Watchlist"');

my $hub  = new_hub('empty');
my $user = Socialtext::User->new( username => 'devnull1@socialtext.com' );
my $ws   = Socialtext::Workspace->new( name => 'empty' );

my $watchlist = Socialtext::Watchlist->new(
    user      => $user,
    workspace => $ws );

my $page       = $hub->pages->new_from_name('Empty Wiki');
my $other_page = $hub->pages->new_from_name('Help');

# Watchlist: empty
ok( ! $watchlist->has_page( page => $page ),
    'Empty Wiki is not in the watchlist' );

cmp_ok( $watchlist->has_page( page => $page ), 'eq', '0',
    'false returned from has_page check' );

my @list = $watchlist->pages;
ok (!grep (/empty_wiki/, @list),
    'The list of watchlist pages does not have admin wiki');

$watchlist->add_page( page => $page );

# Watchlist: empty_wiki
ok( $watchlist->has_page( page => $page ),
    'Empty Wiki is now in the watchlist' );

$watchlist->add_page( page => $other_page );
ok( $watchlist->has_page( page => $other_page ),
    '$other_page is now in the watchlist' );

# Watchlist: empty_wiki, help
@list = $watchlist->pages;
ok( ( grep /empty_wiki/, @list ), 'Empty wiki is still in the watchlist' );
@list = $watchlist->pages(limit => 2);
ok( ( grep /empty_wiki/, @list ), 'Empty wiki is still in the watchlist with limit' );

Users_watching_page: {
    # test using the data created so far in this test
    my $users = Socialtext::Watchlist->Users_watching_page(
        $ws->workspace_id, $page->id,
    );
    is_deeply $users, [$user->user_id],
        "Users_watching_page works";
}

$watchlist->remove_page( page => $page );

# Watchlist: help
ok( !$watchlist->has_page( page=> $page),
    ' Empty Wiki was removed from watchlist' );

@list = $watchlist->pages;
ok( ( grep /help/, @list ), 'Help is still in the watchlist' );
@list = $watchlist->pages(limit => 1);
ok( ( grep /help/, @list ), 'Help is still in the watchlist with limit' );
