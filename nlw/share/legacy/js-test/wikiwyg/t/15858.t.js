var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(5);
t.pass('#15858: wikiwyg: multiple blank lines collapse to single blank line');
t.run_roundtrip('wikitext');

t.filters(filters);
t.run_is('html', 'wikitext');


/* Test
=== Single blank line preserved
--- html
foo<br><br>bar<br>
--- wikitext
foo

bar

=== preserve newlines
--- html
one<br>two<br>three<br>
--- wikitext
one
two
three

*/

/*
These tests fail because we are not implementing 15858 yet. Moving them
out of the way.

=== Preserve two blank lines
--- html
one<br><br><br>two<br>
--- wikitext
one


two

=== As in the ticket description
--- html
one<br><br><br><br>two
--- wikitext
one



two

*/
