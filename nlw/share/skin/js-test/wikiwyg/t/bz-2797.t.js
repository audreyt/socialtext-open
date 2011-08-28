var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);
t.run_is('html', 'text');

/* Test
=== Gecko: Linebreaks are incorrectly parsed when followed by H1
--- html
<div class="wiki"><h1>Foo</h1>Bar
Baz</div>
--- text
^ Foo

Bar Baz

*/
