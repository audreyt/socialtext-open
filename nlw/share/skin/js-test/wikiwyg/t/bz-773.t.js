var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(3);

t.run_is('html', 'text');

/* Test
=== Sanity
--- html
X
Y
Z

--- text
X Y Z

=== Bold tag should not cause linebreak
--- html
X
<b>Y</b>
Z

--- text
X *Y* Z

=== Font tag should not cause linebreak
--- html
<font face="Arial, Helvetica, sans-serif" size="2">X
Y
Z</font>

--- text
X Y Z

*/
