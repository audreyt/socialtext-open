var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== wikitext from bug description
--- wikitext
*Some bold text*.
A sentence no verb
foo bar baz

*some text*.

* [A link]

* [Another link]


*/
