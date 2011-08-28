#!perl
# @COPYRIGHT@

use warnings;
use strict;

use Test::Socialtext;
use Socialtext::Page;
fixtures(qw( empty ));

plan tests => 5;


my @blocks = eval { blocks };
is("$@", "");

my $block = shift @blocks or exit;

my $hub = create_test_hub();
my $page = $hub->pages->new_from_name('something');
$page->content($block->page);

like($page->content, $block->match, $block->description);
unlike($page->content, qr/\n\z/);

$page->store( user => $page->hub->current_user );

like($page->content, $block->match);
like($page->content, qr/\n\z/);


__DATA__



=== Test One

This test shows that a page can be created from text with no final newline.
The newline gets added when the text is stored.

--- page chomp
Subject: A Test Page Without a Final Newline

This is my content.

Since the chomp filter is on above...

There is no newline here -->
--- match literal_lines_regexp
This is my content.
Since the chomp filter is on above...
There is no newline here

