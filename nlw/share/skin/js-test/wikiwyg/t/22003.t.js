var t = new Test.Wikiwyg();

t.plan(1);

t.run_roundtrip('wikitext1', 'wikitext2');

/* Test
=== failure from big test
--- wikitext1
^^ Heading

This is a paragraph:
{category_list: welcome}

--- wikitext2
^^ Heading

This is a paragraph:

{category_list: welcome}

*/
