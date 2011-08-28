var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);
t.run_is('html', 'text');

/* Test
=== Bold variations
--- html
x <b>y</b> z<br />
x<b> y</b> z<br />
x <b> y </b> z<br />
x <b>y </b>z<br />
x<b>y</b> z<br />
x <b>y</b>z<br />
x<b>y</b>z<br />
--- text
x *y* z
x *y* z
x *y* z
x *y* z
xy z
x yz
xyz

*/
