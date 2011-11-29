// https://uj-trac.socialtext.net:447/trac/ticket/478

var t = new Test.Wikiwyg();

t.plan(4);

t.run_roundtrip('wikitext');

/* Test
=== Wafl phrase, then new line
--- wikitext
foo {file: bar}
baz

=== Wafl phrase, then space
--- wikitext
foo {file: bar} baz

=== Wafl phrase, then blank
--- wikitext
foo {file: bar}

baz

=== Wafl phrase, then wafl phrase
--- wikitext
foo {file: bar}

{file: baz}

*/
