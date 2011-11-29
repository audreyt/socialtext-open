var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(6);

t.filters(filters);
t.run_is('html', 'wikitext');
t.run_roundtrip('wikitext');


/* Test
=== A bold becomes a bullet
--- html
<div class="wiki">
<p><span style="font-weight: bold;">
Bold me</span>: xxx</p>
<br></div>
--- wikitext
*Bold me*: xxx

=== A italic
--- html
<div class="wiki">
<p><span style="font-style: italic;">
Italic Me</span>: xxx</p>
<br></div>
--- wikitext
_Italic Me_: xxx

=== A line-through
--- html
<div class="wiki">
<p><span style="text-decoration: line-through;">
Thru Me</span>: xxx</p>
<br></div>
--- wikitext
-Thru Me-: xxx

*/

