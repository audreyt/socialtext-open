var t = new Test.Wikiwyg();

t.plan(1);
t.run_roundtrip('wikitext');

/* Test
=== #15059: Wikiwyg: FF 1.0.7 Break after WAFL
--- wikitext
discussed {rt: 15002} with Brandon. Our app needs to less rude. Concluded the blah blah blah blah blah blah blah blah blah blah blah blah blah blah blah.

*/
