var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== The old big Formatting Test page roundtrips
--- wikitext
{section: top of page anchor test which broke in IE}

See also:

*/
