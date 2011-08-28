#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::More tests => 8;
use Test::Differences;
use Test::Socialtext::Fatal;
use utf8;

use ok 'Socialtext::JSON', qw/encode_json decode_json decode_json_utf8/;

is encode_json({foo=>"bar\n"}), '{"foo":"bar\n"}', 'value with newline';
is encode_json({"foo\n"=>"bar"}), '{"foo\n":"bar"}', 'key with newline';

is encode_json(qq{illegal: " and \n}),
   q{"illegal: \" and \n"},
   "escaped illegal json chars in plain string mode";

is encode_json(qq{illégale: " et \n}),
   Encode::encode_utf8(q{"ill\\u00e9gale: \" et \n"}),
   "escaped illegal json chars in plain string mode (with utf8-encoding)";

ok exception { decode_json('"foo"') }, "can't decode non-refs";

eq_or_diff decode_json_utf8('["föø"]'), ["föø"], "utf8-containing string decodes";
eq_or_diff decode_json_utf8(Encode::encode_utf8('["föø"]')), ["föø"], "utf8-containing string decodes (from bytes)";
