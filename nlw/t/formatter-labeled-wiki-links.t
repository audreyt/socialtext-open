#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;
fixtures(qw( empty ));

my @tests =
    ( [ qq|"A label"[SomePage]\n| =>
        qr(href="[^"]+SomePage[^"]*" wiki_page="SomePage"[^>]*>A label</a>) ],
      [ qq|"A label with space after" [SomePage]\n| =>
        qr(href="[^"]+SomePage[^"]*" wiki_page="SomePage"[^>]*>A label with space after</a>) ],
      [ qq|[NoLabel]\n| =>
        qr(href="[^"]+NoLabel[^"]*" wiki_page=""[^>]*>NoLabel</a>) ],
    );

plan tests => scalar @tests;

for my $test (@tests) {
    formatted_like $test->[0], $test->[1];
}
