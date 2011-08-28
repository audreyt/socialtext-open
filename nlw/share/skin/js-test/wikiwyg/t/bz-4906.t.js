var t = new Test.Wikiwyg();
t.plan(1);
t.run_roundtrip('wikitext');

/* Test
=== HR does not get roundtripped into LIs
--- wikitext
----
{image: a}

*/
