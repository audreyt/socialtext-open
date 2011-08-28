var t = new Test.Wikiwyg();

t.plan(9);

t.run_roundtrip('wikitext');

/* Test
=== mix many phrases
--- wikitext
*"_More Actions_"*

=== concatenate bold and underline
--- wikitext
*foo*_bar_

=== an apostrophe after link
--- wikitext
[link]'s best friend

=== a bolded asis
--- wikitext
*{{XXX}}*

=== a bolded link
--- wikitext
*{link: foo}*

=== two bolded links in the same list
--- wikitext
* *{link: enboldenated wafl yo}*
* *{link: enboldenated wafl yo}*

=== Raw HTML Blocks (one newline)
--- wikitext
.html
<h1>Hello</h1>

<p>I'll find you in heaven.</p>
.html

.html
<!-- A comment -->
<ul>
<li>(double dash bugs)--</li>
</ul>
.html

=== Raw HTML Blocks (two newlines)
--- wikitext
.html
<h1>Hello</h1>

<p>I'll find you in heaven.</p>
.html


.html
<!-- A comment -->
<ul>
<li>(double dash bugs)--</li>
</ul>
.html

=== Raw HTML Blocks (three newlines)
--- wikitext
.html
<h1>Hello</h1>

<p>I'll find you in heaven.</p>
.html



.html
<!-- A comment -->
<ul>
<li>(double dash bugs)--</li>
</ul>
.html

*/

