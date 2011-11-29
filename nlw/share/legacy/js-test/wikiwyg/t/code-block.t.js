var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');


/* Test
=== Code block roundtrip.
--- wikitext
Foo

.code-perl
Bar
.code-perl

Baz

*/
