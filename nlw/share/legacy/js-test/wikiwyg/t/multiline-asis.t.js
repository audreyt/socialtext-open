// https://uj-trac.socialtext.net:447/trac/ticket/326

var t = new Test.Wikiwyg();

var filters = {
    wikitext: ['template_vars']
};

t.plan(1);

t.filters(filters);

t.run_roundtrip('wikitext');


/* Test
=== uj-326 - Multiline asis roundtrips
--- wikitext
{{ *this text is not bold*
_neither is this text italic_ }}

*/

