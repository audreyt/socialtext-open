var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);

t.run_is('html', 'text');

/* Test
=== Non-interesting span elements should be ignored during roundtrip
--- html
<table><tbody><tr><td><span style="padding: 0.5em">1<br/><br/>2</span></td></tr></tbody></table>

--- text
| 1

2 |

*/
