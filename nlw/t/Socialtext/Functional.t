#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::More tests => 4;

our ( $k, $v, $a, $b );

BEGIN { use_ok( 'Socialtext::Functional', 'hgrep', 'foldr', 'sum' ) }

my %filtered_hash = hgrep { $k ne 'foo' } ( foo => 0, bar => 1 );

ok( !exists $filtered_hash{foo}, 'foo got removed.' );
is( 1, $filtered_hash{bar}, 'bar got left alone.' );
is( 1, scalar keys %filtered_hash, 'no other keys.' );
