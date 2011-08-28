var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);
t.run_is('html', 'text');

/* Test
=== Line break inside headings should be empty
--- html
<div class="wiki"><h1><br/></h1>...</div>
--- text
...

*/
