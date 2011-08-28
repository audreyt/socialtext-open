var t = new Test.Wikiwyg();

var filters = {
    badhtml: ['dom_sanitize']
};

// XXX I can't remember exactly what this test was for, but disabling in IE
// since it appears to be fixing a Firefox bug.
if (Wikiwyg.is_ie) {
    t.plan(1);
    t.pass("Skipping these tests on IE");
}
else {
    t.plan(3);
    t.filters(filters);
    t.run_is('badhtml', 'goodhtml');
}

/* Test
=== Inline style on p
--- badhtml
<div class="wiki">
<p style="font-weight: bold;">
Bolding in FF doesn't work</p>
<br></div>
--- goodhtml
<div class="wiki">
<p><span style="font-weight: bold;">Bolding in FF doesn't work</span></p>
<br></div>

=== Inline style on ul
--- badhtml
<ul style="font-weight: bold;"><li>foo<br></li><li>bar<br></li></ul>
--- goodhtml
<ul><li><span style="font-weight: bold;">foo<br></span></li><li><span style="font-weight: bold;">bar<br></span></li></ul>

=== Inline style on li
--- badhtml
<ol><li>foo</li><li style="font-weight: bold;">bar</li><li>baz<br></li></ol>
--- goodhtml
<ol><li>foo</li><li><span style="font-weight: bold;">bar</span></li><li>baz<br></li></ol>

*/
