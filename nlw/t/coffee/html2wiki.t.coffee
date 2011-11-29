async = require('async')
html2wiki = require('html2wiki')

tests = [
  ["<p>Hello <b>world</b></p>", "Hello *world*"]
  ["<h2>Hello</h2>", "^^ Hello"]
  ["<p>^^ Hello</p>", "^^ Hello", true]
  ["<table>\n<tr><td>Jai guru</td></tr></table>", "| Jai guru |"]
  ["<ul><li>deva<ul><li>aum</li></ul></li></ul>", "* deva\n** aum"]
  ["<ol><li>1<ul><li>1A</li></ul></li><li>2</li></ol>", "# 1\n** 1A\n# 2"]
  ["<span style='font-family:comic sans ms,cursive; font-weight: bold'>Comical</span>", "*Comical*", true]
  ["<span style='font-family:!important;'>Comical</span>", "Comical"]
  ["<u>Comical</u>", "Comical", true]
  ['<a name="foo"></a>', "{section: foo}"]
  ["""
<img alt="st-widget-{user: q@q.q}" src="/data/wafl/user%3A%20q%40q.q" class="st-widget" />
  """, "{user: q@q.q}"]
  ["""
<img alt="st-widget-{{Unformatted}}" src="/data/wafl/Unformatted" class="st-widget" />
  """, "{{Unformatted}}"]
  ["<table><tr><td colspan='1'>Colspan=1</td></tr></table>", "| Colspan=1 |"]
  ["<table><tr><td colspan='2'>Colspan=2</td></tr></table>", "| Colspan=2 |", true]
  ["<table><tr><td rowspan='1'>Rowspan=1</td></tr></table>", "| Rowspan=1 |"]
  ["<table><tr><td rowspan='2'>Rowspan=2</td></tr></table>", "| Rowspan=2 |", true]
  ["<table><caption>Caption</caption><tr><td>Cell</td></tr></table>", "Caption\n| Cell |", true]
  ["""
<table style="border-collapse: collapse" options="sort:on border:off" class="formatter_table sort borderless"><tr>\n<td>Cell</td>\n</tr>\n</table>\n
  """, "|| sort:on border:off\n| Cell |"]
  ['<a href="foo">foo</a>', "[foo]"]
  ['<a href="Disable%20Google%20Analytics">Disable Google Analytics</a></li>', '[Disable Google Analytics]']
]

tests = [
  ["""
<img data-wafl=".html
foo
.html" src="/data/wafl/Raw%20HTML%20block.%20Click%20to%20edit." alt="Raw HTML block. Click to edit." class="st-widget" /><img data-wafl="{user: q@q.q}" alt="user: q@q.q" src="/data/wafl/user%3A%20q%40q.q" class="st-widget st-inline-widget" />
  """, """
.html
foo
.html
{user: q@q.q}
  """]
  ["""
    <p><a href="mailto:user.%25%25start_time%25%25@david.socialtext.net">user.%%start_time%%@david.socialtext.net</a></p>
   """, "user.%%start_time%%@david.socialtext.net"]
]

plan tests.length*2

makeStep = ([html, wiki, isErrorExpected]) ->
  (next) -> html2wiki html, (errors, result) ->
    if isErrorExpected
      ok errors, "HTML parses with error (expected)"
    else
      ok not errors, "HTML parses without error"
    eq result, "#{wiki}\n", "result is correct"
    next()

steps = (makeStep t for t in tests)
async.series steps, done_testing
