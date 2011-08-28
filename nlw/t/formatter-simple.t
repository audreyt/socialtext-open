#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 12;
fixtures(qw( empty ));

filters {
    wiki => 'format',
    match => 'wrap_html',
};

my $viewer = new_hub('empty')->viewer;

run_is wiki => 'match';

sub format {
    $viewer->text_to_html(shift)
}

sub wrap_html {
    <<"...";
<div class="wiki">
<p>
$_</p>
</div>
...
}

__DATA__
=== One word strikethrough works.
--- wiki
I mean to say -hello- goodbye.
--- match: I mean to say <del>hello</del> goodbye.

=== Multiword strikethrough works.
--- wiki
-Four score and seven- Eighty-seven years ago...
--- match: <del>Four score and seven</del> Eighty-seven years ago...

=== Hyphenated words are properly struck through.
--- wiki
I mean to say -good-bye- hello.
--- match: I mean to say <del>good-bye</del> hello.

=== Double hyphens do nothing.
--- wiki
I mean --nothing--.
--- match: I mean --nothing--.

=== Whitespace holds off strikethrough.
--- wiki
Please do not - discard - that word.
--- match: Please do not - discard - that word.

=== Complicated example not struck through.
--- wiki
I mean to say --> Master not --> Servant
--- match: I mean to say --&gt; Master not --&gt; Servant

=== Simple teletype WAFL span properly formatted.
--- wiki
`++$bar <h1>yeah</h1>`
--- match: <tt>++$bar &lt;h1&gt;yeah&lt;/h1&gt;</tt>

=== Backticks produce monospace font.
--- wiki
You just say `$foo->bar($baz);`.
--- match: You just say <tt>$foo-&gt;bar($baz);</tt>.

=== Underscores are left alone in backticks.
--- wiki
`_foo_`
--- match: <tt>_foo_</tt>

=== Stars are left alone in backticks.
--- wiki
`*bar*`
--- match: <tt>*bar*</tt>

=== Brackets are left alone in backticks.
--- wiki
`[foo]`
--- match: <tt>[foo]</tt>

=== Not wafl phrase stays not wafl
--- wiki
this is {not-wafl: foo} yeah?
--- match: this is {not-wafl: foo} yeah?
