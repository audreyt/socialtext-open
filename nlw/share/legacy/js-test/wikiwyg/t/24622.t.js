// See {bz: 199} for context.

var t = new Test.Wikiwyg();

Test.Wikiwyg.Filter.prototype.strip_trailing_slash = function(str) {
    return str.replace(/\/>/g, '>');
};

var filters = {
    html: ['html_to_wikitext', 'strip_trailing_slash']
};

t.plan(2);
t.filters(filters);
t.run_is('html', 'wikitext');

/* Test
=== normal links
--- html
<a target="_blank" title="(external link)" href="http://foobar.com">A link</a></p>
<br>Foobar<br class="p"><br class="p">

--- wikitext
"A link"<http://foobar.com>
Foobar

=== rt:24622 duplicated links.
--- html
<a target="_blank" title="(external link)" href="http://foobar.com">A link</a><br>Foobar<br><a target="_blank" title="(external link)" href="http://foobar.com"></a><br class="p"><br class="p">

--- wikitext
"A link"<http://foobar.com>
Foobar

*/
