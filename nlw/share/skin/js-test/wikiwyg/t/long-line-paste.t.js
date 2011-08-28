// From https://uj-trac.socialtext.net:447/trac/ticket/232
var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

if (Wikiwyg.is_gecko) {
    t.plan(8);
    t.filters(filters);
    t.run_roundtrip('wikitext');
    t.run_is('html', 'text');
}
else {
    t.skipAll("On non-gecko browsers.")
}

/* Test
=== document that people are working on
--- wikitext
Up: [Workspace Tour: Table of Contents]
Back: [What else is here?]

You could create a page in a workspace to collaborate on document drafts:

| ^^^ Z-1000 Draft Marketing Collateral

Acme Widgets is proud to present our new, advanced Z-1000 weed-trimmer and hair-styling widget. Its features include:

* a newly-designed rotor with twice the weed-trimming power
* 7 new hair-trimming attachments
* special bulk-pricing options for schools and institutions
|

...not to mention to have [conversations] among team members.

=== meeting agenda page
--- wikitext
Up: [Workspace Tour - Table of Contents]
Back: [Conversations]

* Log the outline of an upcoming meeting or phone conference, and give the address out to participants.
* Make links out to separate pages detailing issues as needed.
* Update the agenda before the meeting, or on the fly during the meeting as new discussion points come up.

| ^^^^ Project Widget Planning Meeting

January 13, 2004
Call-in number: 512-555-1212

* [Widget Product Questions] - Bob
* [Widget Performance Standards] - Akash
* [Widget Production Issues] - Janice
|

...a Workspace can also help you with [project plans]...

=== multi-line table
--- wikitext
foo bar

| lorem ipusm | foo
bar baz | hi |

| lorem ipusm | foo
bar baz | hi |

42 43 44.


=== bigger multi-line table
--- wikitext
Lorem Ipsum foobar. Lorem Ipsum foobar.. Lorem Ipsum foobar.. Lorem Ipsum foobar.. Lorem Ipsum foobar..Lorem Ipsum foobar.. Lorem Ipsum foobar...

| Lorem Ipsum foobar.. Lorem Ipsum foobar.. | 
* Lorem Ipsum foobar..
* Lorem Ipsum foobar..
* Lorem Ipsum foobar..
* Lorem Ipsum foobar.. | Lorem Ipsum foobar..Lorem Ipsum foobar.. |

| Lorem Ipsum foobar.. Lorem Ipsum foobar.. | Lorem Ipsum foobar..
Lorem Ipsum foobar..v Lorem Ipsum foobar..
Lorem Ipsum foobar.. | Lorem Ipsum foobar..Lorem Ipsum foobar.. |

lkadfla

=== bz: 552 description
--- html
aaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeee ffffffffffff gggggggggggggggg hhhhhhhhhhhhhh iiiiiiiiiiiii kkkkkkkkkkkkkkkkk jjjjjjjjjjjjjjjjjjjjjj<br class="p">aaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddd
eeeeeeeeeeeeeeee ffffffffffff gggggggggggggggg hhhhhhhhhhhhhh
iiiiiiiiiiiii kkkkkkkkkkkkkkkkk jjjjjjjjjjjjjjjjjjjjjj<br class="p">
<br>
--- text
aaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeee ffffffffffff gggggggggggggggg hhhhhhhhhhhhhh iiiiiiiiiiiii kkkkkkkkkkkkkkkkk jjjjjjjjjjjjjjjjjjjjjj
aaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbb cccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeee ffffffffffff gggggggggggggggg hhhhhhhhhhhhhh iiiiiiiiiiiii kkkkkkkkkkkkkkkkk jjjjjjjjjjjjjjjjjjjjjj

=== long
--- html
<div class="wiki">Elit tation ipsum dolore aliquam enim dolor accumsan? Esse duis nibh commodo at nulla veniam facilisi tation erat nisl exerci duis euismod eros. Aliquip sed suscipit aliquip ut aliquam sit augue duis at consectetuer. Lobortis autem, duis ea et nibh. Dolor; laoreet zzril, iriure euismod veniam. Zzril veniam vero in blandit lorem. Dignissim feugait enim vero autem zzril amet diam. Suscipit aliquam tincidunt magna feugait consequat adipiscing exerci, feugiat nulla iusto tincidunt!<br class="p"><br class="p">
Elit tation ipsum dolore aliquam enim dolor accumsan? Esse duis nibh
commodo at nulla veniam facilisi tation erat nisl exerci duis euismod
eros. Aliquip sed suscipit aliquip ut aliquam sit augue duis at
consectetuer. Lobortis autem, duis ea et nibh. Dolor; laoreet zzril,
iriure euismod veniam. Zzril veniam vero in blandit lorem. Dignissim
feugait enim vero autem zzril amet diam. Suscipit aliquam tincidunt
magna feugait consequat adipiscing exerci, feugiat nulla iusto
tincidunt!<br class="p"><br class="p">
<br></div>
--- text
Elit tation ipsum dolore aliquam enim dolor accumsan? Esse duis nibh commodo at nulla veniam facilisi tation erat nisl exerci duis euismod eros. Aliquip sed suscipit aliquip ut aliquam sit augue duis at consectetuer. Lobortis autem, duis ea et nibh. Dolor; laoreet zzril, iriure euismod veniam. Zzril veniam vero in blandit lorem. Dignissim feugait enim vero autem zzril amet diam. Suscipit aliquam tincidunt magna feugait consequat adipiscing exerci, feugiat nulla iusto tincidunt!

Elit tation ipsum dolore aliquam enim dolor accumsan? Esse duis nibh commodo at nulla veniam facilisi tation erat nisl exerci duis euismod eros. Aliquip sed suscipit aliquip ut aliquam sit augue duis at consectetuer. Lobortis autem, duis ea et nibh. Dolor; laoreet zzril, iriure euismod veniam. Zzril veniam vero in blandit lorem. Dignissim feugait enim vero autem zzril amet diam. Suscipit aliquam tincidunt magna feugait consequat adipiscing exerci, feugiat nulla iusto tincidunt!

=== another possible results following bz: 552 description
--- html
<div class="wiki">Wisi velit laoreet accumsan autem. Hendrerit te consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim autem in magna dolor in nulla eum vero duis. Ipsum, eum esse ullamcorper tincidunt lorem vel<br class="p"><br class="p">
<br></div>
<div class="wiki">Wisi velit laoreet accumsan autem. Hendrerit te
consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie
illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim
autem in magna dolor in nulla eum vero duis. Ipsum, eum esse
ullamcorper tincidunt lorem vel<br class="p"><br class="p">
<br></div>
<div class="wiki">Wisi velit laoreet accumsan autem. Hendrerit te
consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie
illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim
autem in magna dolor in nulla eum vero duis. Ipsum, eum esse
ullamcorper tincidunt lorem vel<br class="p"><br class="p">
<br></div>

--- text
Wisi velit laoreet accumsan autem. Hendrerit te consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim autem in magna dolor in nulla eum vero duis. Ipsum, eum esse ullamcorper tincidunt lorem vel


Wisi velit laoreet accumsan autem. Hendrerit te consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim autem in magna dolor in nulla eum vero duis. Ipsum, eum esse ullamcorper tincidunt lorem vel


Wisi velit laoreet accumsan autem. Hendrerit te consequat eu, ut illum erat ut duis, ex. Feugiat tincidunt molestie illum odio ut dolor, dolor veniam vero sit illum exerci dolor vel. Enim autem in magna dolor in nulla eum vero duis. Ipsum, eum esse ullamcorper tincidunt lorem vel

=== yet another possible html out of pasting (p inside div.wiki)
--- html
<div class="wiki">aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz<br class="p"><br class="p">
<p>
aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz</p>
<br></div>
<div class="wiki">aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb
ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee
ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa
aaaaaaaaa zzzzzzzzzzz<br class="p"><br class="p">
<p>
aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc
dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff
gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz</p>
<br></div>

--- text
aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz

aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz

aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz

aaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccc dddddddddddddd eeeeeeeeeeeeeeeeeeeeeeeee ffffffffffffff gggggggggggggggggggggg qqqqqqqqqqqqq aaaaaaaaaaaaa aaaaaaaaa zzzzzzzzzzz

*/

