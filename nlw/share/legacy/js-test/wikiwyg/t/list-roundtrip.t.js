// Breaking out smaller test failures from big-formatting-roundtrip.t

var t = new Test.Wikiwyg();

var filters = {
    wikitext: ['template_vars']
};

t.plan(7);

t.filters(filters);

t.run_roundtrip('wikitext');

/* Test
=== RT 20566
--- wikitext
* x
** x
*** x

# The most important Point.
# The next most important point.
## Detail of next most important point.

=== A simple mixed list
--- wikitext
* foo
## bar
* az

=== A bigger mixed list
--- wikitext
# Ordered 1
** Unordered
## Ordered 2
## 1
*** AA
### 21
### 22
## 2
## 3

=== rt 14950
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
## Ordered 2
## 1
*** AA
### 21
### 22
## 2
## 3

=== Wafl phrases
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

=== misc
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

^^ Non WAFL

This is {not-wafl: really no} yo I say {nonono} {no go} eval {this_func()}

.not-a-wafl-block

=== indented block does not roundtrip with an extra paragraph in the beginning
--- wikitext
Lorem Ipsum, Extra paragraph in the beginning..

Normal.

> This text
> should get
> indented.

Back to normal.

*/

/* XXX: This doesn't roundtrip 
=== A crazy mixed list
--- wikitext
# Ordered 1
*** Unordered
** Unordered
##### 1
**** AA
### 21
** AA
#### Ordered 2
# 22
## 2
### 3

*/
