#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];
# Importing Test::Socialtext will cause it to create fixtures now, which we
# want to happen want to happen _after_ Test::Live stops any running
# Apache instances, and all we really need here is Test::More.
use Test::More;
use Socialtext::Workspace;

plan tests => 1;

my $live = Test::Live->new();
my $base_uri = $live->base_url;
# Test::Live sets autocheck to true, which means that Mech blows up on
# 404s, which makes testing for a 404 kind of hard.
$live->mech( WWW::Mechanize->new() );
$live->log_in();

{
    $live->mech()->get( "$base_uri/feed/workspace/admin?page=no_such_page" );

    is( $live->mech()->status(), 404,
        'trying to get a feed for a non-existent page returns a 404' );
}
