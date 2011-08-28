#!perl -w
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 3;
fixtures(qw( empty ));

filters {
    wiki => 'format',
};

my $hub = new_hub('empty');
my $viewer = $hub->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

__DATA__
=== HTML Syntax
--- wiki
.code-html
<b>some html</b>
.code-html
--- match
<div class="wiki">
<div class="wafl_block"><script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shCore.js"></script>
<script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shBrushXml.js"></script>
<link href="/static/skin/common/css/SyntaxHighlighter/shCore.css" rel="stylesheet" type="text/css" />
<link href="/static/skin/common/css/SyntaxHighlighter/shThemeDefault.css" rel="stylesheet" type="text/css" />
<pre class="brush: html">
&lt;b&gt;some html&lt;/b&gt;

</pre>
<script type="text/javascript">SyntaxHighlighter.all()</script>
<!-- wiki:
.code-html
<b>some html</b>
.code-html
--></div>
</div>

=== CSS Syntax
--- wiki
.code-css
p { font-style: italic }
.code-css
--- match
<div class="wiki">
<div class="wafl_block"><script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shCore.js"></script>
<script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shBrushCss.js"></script>
<link href="/static/skin/common/css/SyntaxHighlighter/shCore.css" rel="stylesheet" type="text/css" />
<link href="/static/skin/common/css/SyntaxHighlighter/shThemeDefault.css" rel="stylesheet" type="text/css" />
<pre class="brush: css">
p { font-style: italic }

</pre>
<script type="text/javascript">SyntaxHighlighter.all()</script>
<!-- wiki:
.code-css
p { font-=style: italic }
.code-css
--></div>
</div>

=== Plain text
--- wiki
.code
This is some plain text
.code
--- match
<div class="wiki">
<div class="wafl_block"><script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shCore.js"></script>
<script type="text/javascript" src="/static/skin/common/javascript/SyntaxHighlighter/shBrushPlain.js"></script>
<link href="/static/skin/common/css/SyntaxHighlighter/shCore.css" rel="stylesheet" type="text/css" />
<link href="/static/skin/common/css/SyntaxHighlighter/shThemeDefault.css" rel="stylesheet" type="text/css" />
<pre class="brush: plain">
This is some plain text

</pre>
<script type="text/javascript">SyntaxHighlighter.all()</script>
<!-- wiki:
.code
This is some plain text
.code
--></div>
</div>

