var t = new Test.Wikiwyg();

t.plan(16);
t.run_roundtrip('wikitext');

/*
=== Consecutive HRs
--- wikitext
----
----
----

=== Whitespace around HR (1)
--- wikitext
white
␤----
␤space

=== Whitespace around HR (2)
--- wikitext
white
␤␤----
␤␤space

=== Whitespace around HR (3)
--- wikitext
white
␤␤␤----
␤␤␤space

=== Whitespace around UL (1)
--- wikitext
white
␤* li␤* li
␤space

=== Whitespace around UL (2)
--- wikitext
white
␤␤* li␤* li
␤␤space

=== Whitespace around UL (3)
--- wikitext
white
␤␤␤* li␤* li
␤␤␤space

=== Whitespace around OL (1)
--- wikitext
white
␤# li␤# li
␤space

=== Whitespace around OL (2)
--- wikitext
white
␤␤# li␤# li
␤␤space

=== Whitespace around OL (3)
--- wikitext
white
␤␤␤# li␤# li
␤␤␤space

=== Whitespace around H1
--- wikitext
white
␤^ H1
␤space

=== Whitespace between lists (1)
--- wikitext
white
␤* li␤* li
␤# li␤# li
␤space

=== Whitespace between lists (2)
--- wikitext
white
␤␤* li␤* li
␤␤# li␤# li
␤␤space

=== Whitespace between lists (3)
--- wikitext
white
␤␤␤* li␤* li
␤␤␤# li␤# li
␤␤␤space

=== Matt's Script
--- wikitext
one CRLF
two return

three return










four return











five return












six return













----


three











----


three

# count one
# count two
# count three

# double spaced count


# triple spaced coun



* Four CRLFs between the count and this bullet
* just one CRLF then two CRLFS

* three CRLFS


* four CRLFs



Now some text, then three CRLFS





> one indent, three CRLFs


> Hello at one indent

>> two indents test then three



>> two indents three CRLFS


hello





=== Vertical indented space
--- wikitext
>> Hello
>>
>>

Goodbye

*/
