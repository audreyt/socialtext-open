var t = new Test.Wikiwyg();
t.plan(1);

t.run_roundtrip('wikitext');


/* Test
=== space before a wafl phrases are kept
--- wikitext
foo {image: bar.jpg}

*/

