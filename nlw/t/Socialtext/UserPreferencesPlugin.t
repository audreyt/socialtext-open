#!perl -w
# @COPYRIGHT@

use strict;
use warnings;
use utf8;
use Socialtext::String;

use Test::More tests => 5;

BEGIN {
    use_ok( 'Socialtext::UserPreferencesPlugin' );
}

# aka Favourites, eh?
FAVORITES_PAGE_TITLE:
{
    #
    # Check length boundary conditions.
    # 
    ok(Socialtext::UserPreferencesPlugin->_is_favorites_page_title_valid('a' x Socialtext::String::MAX_PAGE_ID_LEN),
    "Max length title succeeds.");

    ok(! Socialtext::UserPreferencesPlugin->_is_favorites_page_title_valid('a' x (Socialtext::String::MAX_PAGE_ID_LEN + 1)),
    "Over max length title fails.");

    #
    # Check length boundary conditions with Multibyte character.
    # 
    ok(Socialtext::UserPreferencesPlugin->_is_favorites_page_title_valid('あ' x 28),
    "Max length title succeeds.");

    ok(! Socialtext::UserPreferencesPlugin->_is_favorites_page_title_valid('あ' x 29),
    "Over max length title fails.");
}
