var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(2);
t.run_is('html', 'text');

if (Wikiwyg.is_ie) {
    t.run_roundtrip('wikitext_for_ie');
}
else {
    t.run_roundtrip('wikitext');
}


/* Test
=== script pasted in
--- html
<script type="text/javascript">
var a = 0;
</script>!<br>Simple script
--- text
!
Simple script

=== script written in wikitext
--- wikitext
.html
<script type="text/javascript">
var a = 0;
</script>
.html

Simple script

=== script written in wikitext
--- wikitext_for_ie
.html
<p>Hello</p>
<script type="text/javascript">
var a = 0;
</script>
.html

Simple script

*/
