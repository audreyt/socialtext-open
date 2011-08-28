
var t = new Test.Wikiwyg();

if (!Wikiwyg.is_ie) {
    t.skipAll("Not on IE")
}
else {
    t.plan(1);
    t.run_roundtrip('wikitext');
}

/* Test
=== bz 1939
--- wikitext
_foo_

.html
<p>bar</p>
.html

*baz*

*/

