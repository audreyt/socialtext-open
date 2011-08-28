var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(3);
t.pass('#15072: Wikiwyg: Text lines separated by blank lines can collapse into one line');
t.filters(filters);
t.run_is('html', 'wikitext');

/* Test
=== As the first one in the ticket description
--- html
<DIV class=wiki>one</DIV>
<DIV class=wiki>&nbsp;</DIV>
<DIV class=wiki>two</DIV>
<DIV class=wiki>&nbsp;</DIV>
<DIV class=wiki>three</DIV>
--- wikitext
one

two

three
=== As the 'different behaviour' one in ticket description.
--- html
<DIV class=wiki>
<P>!</P><BR>one</DIV>
<DIV class=wiki>two</DIV>
<DIV class=wiki>three</DIV>
<DIV class=wiki>&nbsp;</DIV>
--- wikitext
!

one
two
three

*/
