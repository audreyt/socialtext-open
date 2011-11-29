var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);

t.run_is('html', 'text');

/* Test
=== Empty anchor elements should render into nothing
--- html
<P>Pure<A></A>Nothingness</P>

--- text
PureNothingness

*/
