// https://uj-trac.socialtext.net:447/trac/ticket/412

var t = new Test.Wikiwyg();

t.plan(5);

if (Wikiwyg.is_ie) {
    t.run_roundtrip('wikitext', 'expected_ie');
}
else {
    t.run_roundtrip('wikitext', 'expected');
}

/* Test
=== Indented include roundtrips in IE
--- wikitext
!
 {include: [bogus page name]}

Don't tread on me.
--- expected_ie
!

{include: [bogus page name]}

Don't tread on me.

--- expected
!


{include: [bogus page name]}


Don't tread on me.

=== Include with other text
--- wikitext
La la la {include: [bogus page name]}

Don't tread on me.
--- expected_ie
La la la 

{include: [bogus page name]}

Don't tread on me.

--- expected
La la la

{include: [bogus page name]}


Don't tread on me.

=== Include with other text
--- wikitext
! {include: [bogus page name]} this page.

Don't tread on me.
--- expected_ie
! 

{include: [bogus page name]}

this page.

Don't tread on me.

--- expected
!

{include: [bogus page name]}
this page.

Don't tread on me.

=== Include with other text
--- wikitext
DEE {include: [bogus page name]} DUM

Don't tread on me.
--- expected_ie
DEE 

{include: [bogus page name]}

DUM

Don't tread on me.

--- expected
DEE

{include: [bogus page name]}
DUM

Don't tread on me.

=== Include in a list item
--- wikitext
* DEE {include: [bogus page name]} DUM

Don't tread on the asses
--- expected_ie
* DEE {include: [bogus page name]} DUM

Don't tread on the asses

--- expected
* DEE {include: [bogus page name]} DUM

Don't tread on the asses

*/
