var t = new Test.Wikiwyg();

t.filters({
    text: ['wikitext_to_html']
});

t.plan(1);

t.run_like('text', 'html');

/*
=== YouTube links should allow Embed inside Object tag
--- text
.html
<object><embed></embed></object>
.html

--- html
<div class="wafl_block"><object><embed>
*/
