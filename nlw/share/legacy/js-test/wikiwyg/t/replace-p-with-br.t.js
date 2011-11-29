var t = new Test.Wikiwyg();

t.filters({
    p: ['replace_p_with_br']
});

t.plan(1);

if (jQuery.browser.msie) {
    t.skipAll('On MSIE, replace_p_with_br is not used at all');
}
else {
    t.run_is('p', 'br');
}

/* Test
=== {bz: 911}: Conver P to BR when inline div is present
--- p
<div class="wiki"><p>a</p><p>b<div>c</div>d</p><p>e</p></div>

--- br
<div class="wiki">a<br class="p"><br class="p">b<br class="p"><br class="p"><div>c</div><br class="p"><br class="p">d<br class="p"><br class="p">e<br class="p"><br class="p"></div>

*/
