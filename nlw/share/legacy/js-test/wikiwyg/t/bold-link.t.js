var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== A bold link causes span/span
--- wikitext
* *{link: enboldenated wafl yo}*


*/

