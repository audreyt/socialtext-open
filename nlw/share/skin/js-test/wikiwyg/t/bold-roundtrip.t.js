var t = new Test.Wikiwyg();
t.plan(4);

t.filters({ html: ['html_to_wikitext'] });
t.run_is('html', 'wikitext');
t.run_roundtrip('wikitext');

/* Test
=== foo *bar* baz
--- html
foo <STRONG>bar</STRONG> baz<br class="p"/><BR><br class="p"/>
--- wikitext
foo *bar* baz

=== *foo* bar baz
--- wikitext
*foo* bar baz

=== foo bar *baz*
--- wikitext
foo bar *baz*

*/

