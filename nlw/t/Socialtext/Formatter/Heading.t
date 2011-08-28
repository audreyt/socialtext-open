#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext;
fixtures(qw( empty ));

plan tests => scalar blocks;

filters {
    text => ['format'],
    match => [qw(chomp regexp)],
};

my $hub  = new_hub('empty');
my $viewer  = $hub->viewer;

run_like text => 'match';

sub format {
    $viewer->text_to_html(shift);
}

__DATA__
=== header normal
--- text
^^ Hello There Wilbur

--- match
<h2 id="hello_there_wilbur">Hello There Wilbur</h2>

=== header formatting
--- text
^ Hello *There* Wilbur

--- match
<h1 id="hello_there_wilbur">Hello <strong>There</strong> Wilbur</h1>

=== header with link
--- text
^^^ Hello [There] Wilbur

--- match
<h3 id="hello_there_wilbur">Hello <a href="\?[^"]+page_name=There" wiki_page=""  title="\[click to create page\]" class="incipient">There</a> Wilbur</h3>

=== header as link
--- text
^^ [Hello There Wilbur]

--- match
<h2 id="hello_there_wilbur"><a href="\?[^"]+page_name=Hello%20There%20Wilbur" wiki_page=""  title="\[click to create page\]" class="incipient">Hello There Wilbur</a></h2>

=== header with asis phrase
--- text
^^ Holy {{I am a cow}} Wow

--- match
<h2 id="holy_i_am_a_cow_wow">Holy <span class="nlw_phrase">I am a cow<!-- wiki: {{I am a cow}} --></span> Wow</h2>

=== header as asis phrase
--- text
^^ {{I am a cow}}

--- match
<h2 id="i_am_a_cow"><span class="nlw_phrase">I am a cow<!-- wiki: {{I am a cow}} --></span></h2>
