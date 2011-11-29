var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);

t.run_is('html', 'text');

/* Test
=== Span should not cause non-wrapping of paragraphs
--- html
<span class="small"><p><font color="#cc6600" size="3"><strong>A</strong></font></p>
<p>B
C
D</p><p>E
F
G</p></span>

--- text
*A*

B C D

E F G

*/
