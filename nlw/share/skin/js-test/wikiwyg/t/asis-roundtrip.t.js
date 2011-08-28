var t = new Test.Wikiwyg();

t.plan(4);

t.run_roundtrip('wikitext');

/* Test
=== failure from big test
--- wikitext
{{ {*asis* _without_ -any- [escaped html entities]} }}

{{ {random "insane"<asis> [mark up]} *all* _on_ -one- *line* }}

=== asis paragraph has one blank line
--- wikitext
{{ {one} }}

next line

=== asis phrase
--- wikitext
{{ {one} }} two

next line

=== two asis
--- wikitext
{{ {one} }}

{{ {two} }}

*/

/* Old Test. No longer supported
=== asis phrase with no space after text
--- SKIP
--- wikitext
{{ {one} }}two

next line
*/
