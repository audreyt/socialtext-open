/*
Move the big FormmattingTest page into its own test page. Leave it the
way it was so that we don't regress any. If this test needs to be broken
onto chunks let's do that separately.
*/

var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== {bz: 2586}: Dash in linked page names are roundtripped as "=-" instead of as "-"
--- wikitext
"Foo"[Workspace Tour - Table of Contents]

*/

