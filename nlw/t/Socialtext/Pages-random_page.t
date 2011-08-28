#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
fixtures( 'admin' );

my $hub = new_hub('admin');
my $page = $hub->pages->random_page;

ok( defined($page), 'got a response from random_page' );
ok( $page->isa('Socialtext::Page'), 'page isa Socialtext::Page' );
ok( $page->active, 'page is active' );

