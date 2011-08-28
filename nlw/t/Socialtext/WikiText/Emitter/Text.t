#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext;
use Socialtext::WikiText::Parser::Messages;
use Socialtext::WikiText::Emitter::Messages::Text;

fixtures(qw( empty ));

###############################################################################
my @tests = (
    [ '*WOW*',    'WOW',      'Bold converted to plain-text' ],
    [ '_dude_',   'dude',     'Italics converted to plain-text' ],
    [ '-bummer-', 'bummer',   'Strike-out converted to plain-text' ],
    [ '#hashtag', '#hashtag', 'Hash-mark left as-is' ],
    [ '{user: devnull1@socialtext.com}',
      'devnull1',
      'User wafl expanded to BFN'
    ],
    [ '"This is cool"{link: admin [Some Page]}',
      '"This is cool"',
      'Wiki-link with explicit title'
    ],
    [ '{link: admin [Some Page]}',
      '"Some Page"',
      'Wiki-link with default title'
    ],
    [ '"Google"<http://www.google.com/>',
      '"Google"',
      'URL with explicit title'
    ],
    [ '<http://www.google.com/>',
      '"http://www.google.com/"',
      'URL with default title'
    ],
);
plan tests => scalar @tests;

foreach my $test (@tests) {
    my ($wikitext, $plaintext, $message) = @{$test};
    my $parser = Socialtext::WikiText::Parser::Messages->new(
        receiver => Socialtext::WikiText::Emitter::Messages::Text->new(),
    );
    my $rendered = $parser->parse($wikitext);
    is $rendered, $plaintext, $message;
}
