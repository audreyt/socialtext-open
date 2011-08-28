#!perl
# @COPYRIGHT@

use warnings;
use strict;
use Test::Socialtext tests => 6;

use Encode;
use Socialtext::CategoryPlugin;

my $singapore = join '', map { chr($_) } 26032, 21152, 22369;

# not remotely exhaustive...
my @tests = (
    [ "Pete's Blog" => "Pete=27s_Blog" ],
    [ "Art & Science" => "Art_=26_Science" ],
    [ $singapore => "=E6=96=B0=E5=8A=A0=E5=9D=A1" ],
);

{
    for my $test (@tests)
    {
        my $label = $test->[0];
        Encode::_utf8_off($label);

        my $result = Socialtext::CategoryPlugin->Encode_category_email( $test->[0] );
        is ( $result, $test->[1], "$label - encode" );
        $result = Socialtext::CategoryPlugin->Decode_category_email( $test->[1] );
        is ( $result, $test->[0], "$label - decode" );
    }
}
