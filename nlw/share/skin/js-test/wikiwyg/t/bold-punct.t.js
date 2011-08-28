var t = new Test.Wikiwyg();

t.plan(4);

t.run_roundtrip('wikitext');

/* Test
=== Bold followed by ':' roundtrips.
--- wikitext
*NOTE*: This must be bold.

=== Bold followed by '!' roundtrips.
--- wikitext
You need to *keep it simple*!

=== Italic followed by ':' roundtrips.
--- wikitext
_NOTE_: This must be bold.

=== Italic followed by '!' roundtrips.
--- wikitext
You need to _keep it simple_!

*/
