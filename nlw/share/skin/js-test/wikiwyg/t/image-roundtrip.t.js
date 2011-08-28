// From https://uj-trac.socialtext.net:447/trac/ticket/232
var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(3);
t.filters(filters);
t.run_roundtrip('wikitext');
t.run_is('html', 'text');

/* Test
=== uj-232 - Image urls not roundtripping in IE
--- wikitext
http://www.socialtext.com/images/logo.png

> http://www.socialtext.com/images/logo.png

=== wafl inside a P tag works
--- html
<p><span><img alt="base" src="http://www.socialtext.com/images/logo.png" border="0"><!-- wiki: http://www.socialtext.com/images/logo.png --></span></p>
--- text
http://www.socialtext.com/images/logo.png

=== wafl inside a BLOCKQUOTE tag works
--- html
<blockquote><span><img alt="base" src="http://www.socialtext.com/images/logo.png" border="0"><!-- wiki: http://www.socialtext.com/images/logo.png --></span></blockquote>
--- text
> http://www.socialtext.com/images/logo.png

*/

