#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;
fixtures(qw( empty ));

my @tests =
    ( [ "An aim link aim:foobar\n" =>
        qr{\Qaim:goim?screenname=foobar\E.+\Qbig.oscar.aol.com/foobar\E} ],
      [ "A yahoo IM link yahoo:barfoo\n" => qr{\Qymsgr:sendIM?barfoo\E} ],
      [ "Another yahoo IM link ymsgr:bubba\n" => qr{\Qymsgr:sendIM?bubba\E} ],
      [ "A skype link callto:JoeSmith\n" => qr{href="callto:JoeSmith"} ],
      [ "A skype link (phone #) callto:1-612-555-9911\n" => qr{href="callto:1-612-555-9911"} ],
      [ "An msn link msn:BillE-G\n" => qr{msn:BillE-G} ],
    );

plan tests => scalar @tests;

for my $test (@tests) {
    formatted_like $test->[0], $test->[1];
}
