/*
Move the big FormmattingTest page into its own test page. Leave it the
way it was so that we don't regress any. If this test needs to be broken
onto chunks let's do that separately.
*/

var t = new Test.Wikiwyg();

t.plan(1);

var filters = {
    wikitext: ['template_vars']
};

t.filters(filters);


t.run_roundtrip('wikitext');


/* Test
=== Except for this failure chunk
--- wikitext
"Name of this Link"<[%BASE_URL%]/admin/index.cgi?page_name>

*/

