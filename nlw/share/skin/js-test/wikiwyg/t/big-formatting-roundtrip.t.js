/*
Move the big FormmattingTest page into its own test page. Leave it the
way it was so that we don't regress any. If this test needs to be broken
onto chunks let's do that separately.
*/

var t = new Test.Wikiwyg();

t.plan(16);

t.run_roundtrip('wikitext');

/* Test
=== The old big Formatting Test page roundtrips, part 1
--- wikitext
{section: top of page anchor test which broke in IE}

See also: FormattingTest | [FormattingToDo] | [WikiwygFormattingTest] | [WikiwygFormattingToDo]

^^^^ Everything in this file should roundtrip flawlessy (clean diff -u)
----

^^ Whitespace issues go here:

^^^ {rt: 14945}

*"_More Actions_"*
*foo*_bar_
[link]'s best friend

^^ Links:

* NotALink
* [FormattingToDo]
* [this is a link]
* [a > little < bit * of ! funny & punctuation?]
* http://foo.com/
* https://securefoo.com/
* http://foo.com/with?parameters=hanging&around
* "Renamed Formatting Tüst"[formattingtest]
* "Renamed Broken Link"[this is a link]
* "Renamed Web Link"<http://foo.com/>
* "Renamed funny punctuation"[what s the funny punctuation]
* "Renamed UTF-8"[Проекты - ЛЦ]
* Question after URL <http://foo.com>?
* casey.west@socialtext.com
* "Casey West Email"<mailto:casey.west@socialtext.com>
* Relative links: "home"<http:index.cgi> | http:index.cgi | http:/static/images/logo-bar-18.gif
* Interwiki link, with permission: {link: public [wiki 101]}
* Interwiki links, without permission: {link: dev-tasks [wiki 101]}
* {link: public [wiki 101] anchor}
* ([link contained in parens])
* _<http://sunirlikesthemitalicizedurls.com>_
* {weblog: Socialtext weblog}
* {file: Rule #1}
* {file: Robot.txt}
* "Named link"[with: colon]
* 'http://no.space.before.link is a great site'
* '<http://no.space.before.link>'
* This is a file link file://thisisaserver/filename.txt
* This is a "named file link"<file://thisisaserver/filename.txt>
* "Save the dash in this renamed link"[Workspace Tour - Table of Contents]

=== The old big Formatting Test page roundtrips, part 2
--- wikitext
^^ Presence links

* Aim
** aim:sleepleft
* Yahoo
** yahoo:chrislondonbridge
** ymsgr:chrislondonbridge
* Skype
** skype:chrisdent
** callto:chrisdent

^ Header 1

^^ Header 2

^^^ Header 3

^^^^ Header 4

^^^^^ Header 5

^^^^^^ Header 6

=== The old big Formatting Test page roundtrips, part 3
--- wikitext
^^ Lists

* One Simple
* Two Unordered
* Three List

# One Simple
# Two Ordered
# Three List

* One Complex
** Nested List
* Which comes back

^^^ RT 14545

This paragraph is significant.

## Alpha
## ...
## Omega

=== The old big Formatting Test page roundtrips, part 4
--- wikitext
^^^ {rt: 14950}

* One Simple
* Two Unordered
* Three List

# One Simple
# Two Ordered
# Three List

* One Complex
** Nested List
* Which comes back

# Ordered 1
** Unordered
# Ordered 2

# 1
** AA
## 21
## 22
# 2
# 3

^^ Phrases

This paragraph contains content which is *bold*. It also has _italic_ content.
And for fun we've got *_bold italic_*. And lest we forget, there's always
-strike through-

And then there are* cases *where bolding shouldn't happen. There are times
when --> you don't expect --> strikethrough, but it happens.

Go to <http://foo.com/>.

*yo*. /yo/ . yo

This is *bold* _italic_ -strike- `monospace` yo

Leave `*stars*` and `_unders_` alone inside my backticks please.

=== The old big Formatting Test page roundtrips, part 5
--- wikitext
^^ Tables

A Simple table

| *header one* | *header two* |
| row item one | row item two |

Multiline cells

| this | that | the other |
| one fish
two fish | red

fish | [blue dotted underlined]
_fish_ |

{rt: 15410}

| 15410 | .pre
content
.pre |

=== The old big Formatting Test page roundtrips, part 6
--- wikitext
^^ Blockquote Test

Normal.

> This text
> should get
> indented.

Back to normal.

Normal.

> level one.
> level one..
>> level two.
>> level two..
> level one...
>>> level three.

Back to normal.

=== The old big Formatting Test page roundtrips, part 7
--- wikitext
^^ Wafl phrases

* image wafl (exists): {image: test_image.jpg}
* image wafl (doesn't exist): {image: not_an_image.jpg}
* From {rt: 12907}
* {rt: 12345} Foo Bar baz
* {image: thing.png} is so bad ass
* Burger Sheep {tm}
* Expecting no space after this: {link: asdf}
* Escaped wafl {{{foo}}}
* *{link: enboldenated wafl yo}*
* *{link: enboldenated wafl yo}* yo yo yo
* yo yo yo {link: wafl yo} yo yo yo

=== The old big Formatting Test page roundtrips part 8
--- wikitext
^^ Non WAFL

This is {not-wafl: really no} yo I say {nonono} {no go} eval {this_func()}

.not-a-wafl-block

=== The old big Formatting Test page roundtrips, part 9
--- wikitext
^^ {rt: 14913}

Preserve pairs of angle brackets:
<h1>
<ugly style="stupid">
<>
<.>
< >
<<<>

=== The old big Formatting Test page roundtrips part 10
--- wikitext
^^ {rt: 14914}

Make wafl phrase markup stricter:

This {link[not]} {link,nope} {not.wafl.either}

Real wafl {{ {link:foo} or {link: foo} or {link foo} or {tm};}} only

=== The old big Formatting Test page roundtrips part 11
--- wikitext
^^ {rt: 14915}

Preserve lines of phrase markers (10 each below):

xxx **********
xxx ----------
xxx __________
xxx__________
__________

=== The old big Formatting Test page roundtrips part 12
--- wikitext
^^ {rt: 14365}

{link: Foo}
{link: Bar}
{link: Baz}

^^^ Unadorned Image URL's

* http://www2.socialtext.net/dev-tasks/Onit_Logo.png

^^^ Section links

^^^^^ The *Main* Event

We are having an event...

^^^^^ Where?

The Shopping Mall

^^^^^ When (date/time)?

Saturday, May 14th 2pm

^^^^^ Обложка

{section: this}

(section this)

{section: this thing}

(section this thing)

{section: This Here Thang}

(section This Here Thing)

^^ asis

> {{ {random "indented"<asis> [mark up]} }}

XXX - this isn't doing quite what it thinks it is:

{{

=== The old big Formatting Test page roundtrips, part 13
--- wikitext
^^ multiline

*asis* _without_ -any- [escaped html entities]

| Here is | how you | enter |
| a table. | It takes | Multiple lines |
| to | be | useful. |

}}

=== The old big Formatting Test page roundtrips part 14
--- wikitext
^^ Wafl blocks.

^^^ Pre formatted

Below are four lines. Each line starts with
that last character of the previous.

.pre
once
   there
       was
         something true
           note
          that
        you
    can       edit
 this  in    wy si wyg
        mode.
     ----- __@       __@       __@        __@       _~@
    ---- _`\<,_    _`\<,_    _`\<,_     _`\<,_    _`\<,_
   ---- (*)/ (*)  (*)/ (*)  (*)/ (*)  (*)/ (*)  (*)/ (*)
!@#$%^&*()_+-={}[]||;':",./<>?~`!@#$%^&*()_+-={}[]||;':",./<>?~`
.pre


.pre
&lt;some text between carets&gt;
.pre


&lt;some text between carets&gt;

=== The old big Formatting Test page roundtrips part 15
--- wikitext
^^^ Raw HTML

.html
<h1>Hello</h1>

<p>I'll find you in heaven.</p>
.html

.html
<!-- A comment -->
<ul>
<li>(double dash bugs)--</li>
</ul>
.html

=== Except for this failure chunk
--- wikitext
* *{link: enboldenated wafl yo} yo yo yo {link: enboldenated wafl yo}*

*/

