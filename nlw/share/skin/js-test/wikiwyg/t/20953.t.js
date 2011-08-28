var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== rt:20953 empty heading
--- wikitext
^^^

----

Stuff

*/
