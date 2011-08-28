var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(3);

t.pass("#14988: Wikiwyg: Can't create whitespace separated lists in Simple mode");
t.filters(filters);
t.run_is('html', 'wikitext');

t.run_roundtrip('wikitext');

/* Test
=== Two seperating list as in the ticket description.
--- html
<ul><li>one</li><li>two</li></ul><ul><li>three</li><li>four</li></ul>
--- wikitext
* one
* two

* three
* four

*/
