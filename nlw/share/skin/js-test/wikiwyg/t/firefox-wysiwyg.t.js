var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(1);

t.filters(filters);

t.run_is('html', 'wikitext');

// t.run_roundtrip('wikitext');

/* Test
=== mix many phrases
--- html
<span style="font-weight: bold;">"<span style="font-style: italic;">More Actions</span>"</span></p>
--- wikitext
*"_More Actions_"*

*/

