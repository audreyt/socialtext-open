#!perl
# @COPYRIGHT@
use strict;
use warnings;
use mocked 'Socialtext::User';

# use Test::Socialtext tests => 12;
use Test::Base;
use Socialtext::WikiText::Parser::Messages;
use Socialtext::WikiText::Emitter::Messages::Solr;
# use WikiText::WikiByte::Emitter;

filters {
    wikitext => 'format',
};

run_is wikitext => 'solr';
exit;

sub format {
    my $parser = Socialtext::WikiText::Parser::Messages->new(
       receiver => Socialtext::WikiText::Emitter::Messages::Solr->new,
#       receiver => WikiText::WikiByte::Emitter->new,
    );
    return $parser->parse($_);
}

__DATA__
=== Asis phrase wikitext stripped
--- wikitext: I mean to say {{hello goodbye}}.
--- solr: I mean to say hello goodbye.

=== Bold phrase wikitext stripped
--- wikitext: I mean to say *hello* goodbye.
--- solr: I mean to say hello goodbye.

=== Italic phrase wikitext stripped
--- wikitext: I mean to say _hello_ goodbye.
--- solr: I mean to say hello goodbye.

=== Strikethrough phrase wikitext stripped
--- wikitext: I mean to say -hello- goodbye.
--- solr: I mean to say hello goodbye.

=== User mentions are supported
--- wikitext: Hi there {user: 42}!
--- solr: Hi there Best FullName!

=== Named links are supported
--- wikitext: Have you seen "This crazy site"<http://foo.com/carl> now?
--- solr: Have you seen "This crazy site"<http://foo.com/carl> now?

=== Raw links are supported
--- wikitext: Have you seen "http://foo.com/carl"<http://foo.com/carl> yet?
--- solr: Have you seen "http://foo.com/carl" yet?

=== page links are supported
--- wikitext: edited "Some Label"{link: workspacename [some_page]}
--- solr: edited "Some Label" workspacename [some_page]

