var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(6);
t.filters(filters);
if (jQuery.browser.msie) {
    t.skipAll('MSIE uses its own vertical-whitespace logic')
}
else {
    t.run_is('html', 'wikitext');
}



/* Test
=== Vertical whitespace in Chrome (part 1)
--- html
0<div></div><div><br></div><div><br></div><div><br></div><div>3</div>
--- wikitext
0
␤␤␤3

=== Vertical whitespace in Chrome (part 2)
--- html
<div class="wiki">0</div><div class="wiki"><br></div><div class="wiki"><br></div><div class="wiki"><br></div><div class="wiki">3</div><div class="wiki"><br></div><div class="wiki"><br></div><div class="wiki">2</div>
--- wikitext
0
␤␤␤3
␤␤2

=== Vertical whitespace in Chrome (part 3)
--- html
<div class="wiki">1<br class="p"><br></div><div class="wiki"><br class="p">2<br class="p"><br class="p">3</div>
--- wikitext
1
␤␤2
␤3

=== Vertical whitespace in Firefox (part 1)
--- html
<div class="wiki">0<br><br><br><br>3<br><br><br><br><br>4<br></div>
--- wikitext
0
␤␤␤3
␤␤␤␤4

=== Vertical whitespace in Firefox (part 2)
--- html
<div class="wiki">
<p>
0<br>
<br>
<br>
<br>
</p>
<p>
4<br>
<br>
<br>
<br>
<br>
</p>
<p>
5</p>
</div>
--- wikitext
0
␤␤␤␤4
␤␤␤␤␤5

=== Vertical whitespace in Chrome+Firefox (1)
--- html
<div class="wiki">
<br /><p>
1</p>
<br/></div>
--- wikitext
␤1

*/
