var t = new Test.Wikiwyg();
t.plan(1);
t.filters({ wikitext: ['template_vars'] });
t.run_roundtrip('wikitext');

/* Test
=== Except for this failure chunk
--- wikitext
"Conversations"<[%BASE_URL%]admin/index.cgi?Babel>

*/

