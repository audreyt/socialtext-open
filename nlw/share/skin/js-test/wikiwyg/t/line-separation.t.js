var t = new Test.Wikiwyg();

t.plan(2);

t.run_roundtrip('wikitext');

/* Test
=== A table and a wafl
--- wikitext
␤| a | table |

{rt: 11111}

=== Two asises
--- wikitext
{{ ... }}

{{ ,,, }}

*/
