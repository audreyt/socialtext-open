// https://uj-trac.socialtext.net:447/trac/ticket/413

var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== Single include roundtrips in IE
--- wikitext
{include: [bogus page name]}

*/
