var t = new Test.Wikiwyg();

t.filters({
    text: ['wikitext_to_html']
});

t.plan(6);

t.run_like('text', 'html');

/*
=== Single-line table formatting: UL
--- text
| * foo |
--- html
<ul>
=== Single-line table formatting: OL
--- text
| # foo |
--- html
<ol>
=== Multi-line table formatting: UL
--- text
| * foo
* bar |
--- html
<ul>
=== Multi-line table formatting: OL
--- text
| # foo
# bar |
--- html
<ol>
=== Single-line table formatting: UL UL
--- text
| ** foo |
--- html
<ul>
=== Single-line table formatting: OL OL
--- text
| ## foo |
--- html
<ol>
*/
