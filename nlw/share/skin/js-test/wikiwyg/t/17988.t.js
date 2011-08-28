var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');


/* Test
=== Roundtrip adjacent lists
--- wikitext
* foo

* bar

*/
