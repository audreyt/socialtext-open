var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(2);
t.run_is('html', 'text');

/* Test
=== "font" tags in .html wafl blocks shouldn't be stripped.
--- html
<div class="wafl_block"><div>I like <font color="blue">blue</font>. </div>
<!-- wiki:
.html
I like <font color=="blue">blue</font>.
.html
--></div>
--- text
.html
I like <font color="blue">blue</font>.
.html

=== However, "xml" tags should be stripped by the MS-Office cleanup filter.
--- html
<div class="wafl_block"><div>I like <xml><font color="blue">blue</font></xml>. </div>
<!-- wiki:
.html
I like <xml><font color=="blue">blue</font></xml>.
.html
--></div>
--- text
.html
I like <font color="blue">blue</font>.
.html

*/
