#!perl
# @COPYRIGHT@
use strict;
use warnings;
use lib 't/lib';
use Test::WikiText;

plan tests => 1;

#no_diff;

$Test::WikiText::parser_module =
    'Socialtext::WikiText::Parser';
$Test::WikiText::emitter_module =
    'Socialtext::WikiText::Emitter::Messages::Canonicalize';;

filters({wikitext => 'parse_wikitext', canonicalized => 'chomp'});

run_is 'wikitext' => 'canonicalized';

__DATA__
=== Basic Formatting

--- wikitext
"Named"<http://example.org> http://example.com/ _*italic bold*_

--- canonicalized
"Named"<http://example.org> "http://example.com/"<http://example.com/> _*italic bold*_
