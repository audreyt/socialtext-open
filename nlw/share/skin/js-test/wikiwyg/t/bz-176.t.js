var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(7);

t.run_is('html', 'text');

/* Test
=== H1 Bold with span
--- html
<h1><span style="font-weight: bold;">X</span></h1>

--- text
^ *X*

=== H1 Bold with attr
--- html
<h1 style="font-weight: bold;">X</h1>

--- text
^ *X*

=== H6 Bold+Italic+LineThrough with span
--- html
<h6><span style="font-weight: bold; font-style: italic; text-decoration: line-through">X</span></h6>

--- text
^^^^^^ -_*X*_-

=== H6 Bold+Italic+LineThrough with attr
--- html
<h6 style="font-weight: bold; font-style: italic; text-decoration: line-through">X</h6>

--- text
^^^^^^ -_*X*_-

=== A Bold with span (inner)
--- html
<a class="incipient" title="[click to create page]" href="index.cgi?action=display;is_incipient=1;page_name=a"><span style="font-weight: bold;">X</span></a>

--- text
*"X"[a]*

=== A Bold with span (outer)
--- html
<span style="font-weight: bold;"><a class="incipient" title="[click to create page]" href="index.cgi?action=display;is_incipient=1;page_name=a">X</a></span>

--- text
*"X"[a]*

=== A Bold with attr
--- html
<a style="font-weight: bold;" class="incipient" title="[click to create page]" href="index.cgi?action=display;is_incipient=1;page_name=a">X</a>

--- text
*"X"[a]*


*/
