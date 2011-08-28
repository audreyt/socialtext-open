var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext');

/* Test
=== rt:24146 wiki punk
--- wikitext
*single*
_single_
-single-
*single*.
_single_.
-single-.
*single*?
_single_?
-single-?
*single*!
_single_!
-single-!
*single*;
_single_;
-single-;
*single*:
_single_:
-single-:
*.single*
_.single_
-.single-

*/
