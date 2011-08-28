var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== Just testing a wikilink
--- wikitext
You can link [With a Link].

*/

