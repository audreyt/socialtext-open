var t = new Test.Wikiwyg();

var filters = {
    html: ['dom_sanitize'],
    fixed: []
};

if (Wikiwyg.is_ie)
    filters.fixed.push( function() { return this.data.fixed_ie });
if (Wikiwyg.is_safari && !Wikiwyg.is_safari3 ) 
    filters.fixed.push( function() { return this.data.fixed_safari });

t.plan(2);
t.pass('#16155: wikiwyg: bold becomes bullet due to space insertion');
t.filters(filters);
t.run_is('html', 'fixed');

/* Test
=== Two seperating list as in the ticket description.
--- html
<p><span style="font-weight: bold;">
xxx yyy</span><br></p>
<br>
--- fixed
<p><span style="font-weight: bold;">xxx yyy</span><br></p>
<br>
--- fixed_ie
<P><SPAN style="FONT-WEIGHT: bold">xxx yyy</SPAN><BR></P><BR>
--- fixed_safari
<P><SPAN style="font-weight: bold;">xxx yyy</SPAN><BR></P>
<BR>

*/
