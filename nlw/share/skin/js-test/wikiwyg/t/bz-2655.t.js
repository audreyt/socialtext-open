var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);
t.run_is('html', 'text');

/* Test
=== Bold, italics and strikethrough in the TD level are correctly preserved
--- html
<div class="wiki">
<table border="1" class="formatter_table" options="" style="border-collapse: collapse;">
<tbody><tr>
<td><span style="font-weight: bold">Bold</span></td>
<td><span style="font-style: italic">Italic</span></td>
<td><strike>Strikethrough</strike></td>
</tr>
</tbody></table>
</div>

--- text
| *Bold* | _Italic_ | -Strikethrough- |

*/
