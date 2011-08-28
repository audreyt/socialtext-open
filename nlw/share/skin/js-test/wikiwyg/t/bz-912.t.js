var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(2);

t.run_is('html', 'text');

/* Test
=== Spaces around links when surrounded by word characters
--- html
x<a href="y">y</a>z<br/>
x<a href="y">y</a> z<br/>
x <a href="y">y</a>z<br/>
x <a href="y">y</a> z<br class="p"/>
--- text
x [y] z
x [y] z
x [y] z
x [y] z

=== No spaces around links when surrounded by non-word characters
--- html
!<a href="y">y</a>!
--- text
![y]!

*/
