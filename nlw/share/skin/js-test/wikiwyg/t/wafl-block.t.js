var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);

t.run_is('html', 'text');

/* Test
=== WAFL block surrounded by text should generate vertical space
--- html
<P>x<IMG title="Preformatted text. Click to edit." alt="st-widget-.pre&#10;y&#10;.pre" src="http://ubuntu:21000/data/wafl/Preformatted%20text.%20Click%20to%20edit.">z</P>

--- text
x

.pre
y
.pre

z

*/

