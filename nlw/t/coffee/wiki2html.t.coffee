wiki2html = require('wiki2html')

tests = [
  ["Hello *world*", "<p>Hello <b>world</b></p>\n"]
  [".code-perl\nMoose\n.code-perl\n", """
<img data-wafl=".code-perl
Moose
.code-perl" src="/data/wafl/Code%20block%20with%20Perl%20syntax.%20Click%20to%20edit." alt="Code block with Perl syntax. Click to edit." class="st-widget" />
  """]
  ["{user: q@q.q}", """
<img data-wafl="{user: q@q.q}" alt="user: q@q.q" src="/data/wafl/user%3A%20q%40q.q" class="st-widget st-inline-widget" />
  """]
  ["{{Unformatted}}", """
<p><img data-wafl="{{Unformatted}}" alt="Unformatted" src="/data/wafl/Unformatted" class="st-widget st-inline-widget" /></p>\n
  """]
  ["|| sort:on border:off\n| Cell |", """
<table style="border-collapse: collapse" options="sort:on border:off" class="formatter_table sort borderless"><tr>\n<td>Cell</td>\n</tr>\n</table><br />\n
  """]
  ["\"label\"{link: [page]}", """
<img data-wafl="&#34;label&#34;{link: [page]}" alt="label" src="/data/wafl/label" class="st-widget st-inline-widget" />
  """]
  ["text \"label\"{link: [page]}", """
<p>text <img data-wafl="&#34;label&#34;{link: [page]}" alt="label" src="/data/wafl/label" class="st-widget st-inline-widget" /></p>\n
  """]
  ["| multi\nline |", """
<table style="border-collapse: collapse" options="" class="formatter_table" border="1"><tr>\n<td><p>multi<br />\nline</p>\n</td>\n</tr>\n</table><br />\n
  """]
  ["""
| x | y z
[w] |
  """, """
<table style="border-collapse: collapse" options="" class="formatter_table" border="1"><tr>
<td>x</td>
<td><p>y z<br />
<a href="w">w</a></p>
</td>
</tr>
</table><br />\n
  """]
  ["""
"Test" <mailto:foo@bar.org>
  """, """
<p><a href="mailto:foo@bar.org">Test</a></p>\n
  """]
  ["""
foo@bar.org
  """, """
<p><a href="mailto:foo@bar.org">foo@bar.org</a></p>\n
  """]
  ["[XHTML: Meeting notes 2009-01-06]", """
<p><a href="XHTML%3A%20Meeting%20notes%202009-01-06">XHTML: Meeting notes 2009-01-06</a></p>\n
  """]
  ["""
| x | y |
| z | w |
  """, """
<table style="border-collapse: collapse" options="" class="formatter_table" border="1"><tr>
<td>x</td>
<td>y</td>
</tr>
<tr>
<td>z</td>
<td>w</td>
</tr>
</table><br />\n
  """]
  ["""
| x | y |
| z |
  """, """
<table style="border-collapse: collapse" options="" class="formatter_table" border="1"><tr>
<td>x</td>
<td>y</td>
</tr>
<tr>
<td>z</td>
<td></td>
</tr>
</table><br />\n
  """]
  ["""
.html
foo
.html
{user: q@q.q}
  """, """
<img data-wafl=".html
foo
.html" src="/data/wafl/Raw%20HTML%20block.%20Click%20to%20edit." alt="Raw HTML block. Click to edit." class="st-widget" /><img data-wafl="{user: q@q.q}" alt="user: q@q.q" src="/data/wafl/user%3A%20q%40q.q" class="st-widget st-inline-widget" />
  """]
  ["user.%%start_time%%@david.socialtext.net", """
    <p><a href="mailto:user.%25%25start_time%25%25@david.socialtext.net">user.%%start_time%%@david.socialtext.net</a></p>\n
  """]
  ["http://example.com/naïve", "<p><a href=\"http://example.com/na%C3%AFve\">http://example.com/naïve</a></p>\n"]
  ["http://example.com/Hi%20There", "<p><a href=\"http://example.com/Hi%20There\">http://example.com/Hi%20There</a></p>\n"]
  ["\"Hi There\"<http://example.com/Hi%20There>", "<p><a href=\"http://example.com/Hi%20There\">Hi There</a></p>\n"]
]

for [wiki, html] in tests
  eq wiki2html(wiki), html
