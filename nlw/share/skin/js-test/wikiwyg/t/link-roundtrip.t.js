// https://uj-trac.socialtext.net:447/trac/ticket/325
// https://rt.socialtext.net:444/Ticket/Display.html?id=20575

var t = new Test.Wikiwyg();

var filters = {
    wikitext: ['template_vars']
};

t.plan(3);

t.filters(filters);

t.run_roundtrip('wikitext');

// Possible fix: renamed wikilink uses a hint. renamed hyperlink can do the
// same...

/* Test
=== uj-325 - Full urls with fragment in the same workspace.
--- wikitext
"Andy presents us with a problem"<[%BASE_URL%]/index.cgi?alester_2006_09_28#the_business_value_of_happiness>

=== Same but in surrounding context
--- wikitext
foo "Andy presents us with a problem"<[%BASE_URL%]/index.cgi?alester_2006_09_28#the_business_value_of_happiness> bar

=== Renamed relative link
--- wikitext
"hello"<http:index.cgi?ass_page>

*/

