var t = new Test.Wikiwyg();
t.plan(1);
t.run_roundtrip('wikitext');

/* Test
=== wikiwyg does not debold text
--- wikitext
(*please bold*)

*/

