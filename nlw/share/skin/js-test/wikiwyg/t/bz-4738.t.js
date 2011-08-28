var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);
t.run_is('html', 'text');

/* Test
=== Table elements are always formatted as a block, instead of as a single line
--- html
<div class="wiki">
    <h1><strong><table><a><tr><td>ABC</td></tr></a></table></strong></h1>
</div>
--- text
| ABC |

*/
