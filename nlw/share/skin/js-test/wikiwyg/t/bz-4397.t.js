var t = new Test.Wikiwyg();

t.filters({
    text: ['wikitext_to_html_js']
});

t.plan(7);

t.run_like('text', 'html');

/*
=== Normal linebreaks
--- text
line1
line2
--- html
line1<br />
line2</p>

=== Phrase markup across lines should have no effect (asterisk)
--- text
*line1
line2*
--- html
\*line1<br />
line2\*</p>

=== Phrase markup across lines should have no effect (underscore)
--- text
_line1
line2_
--- html
_line1<br />
line2_</p>

=== Phrase markup across lines should have no effect (dash)
--- text
-line1
line2-
--- html
-line1<br />
line2-</p>

=== Phrase markup across lines should have no effect (backtick)
--- text
`line1
line2`
--- html
`line1<br />
line2`</p>

=== Phrase markup across lines should have no effect (double braces)
--- text
{{line1
line2}}
--- html
{{line1<br />
line2}}</p>

=== Phrase markup across lines should have no effect (wafl)
--- text
{date:
2010-09-15 10:36:30 GMT}
--- html
{date:<br />
2010-09-15 10:36:30 GMT}</p>

*/
