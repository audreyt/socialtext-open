var t = new Test.Wikiwyg();

t.plan(5);

t.run_roundtrip('wikitext');


/* Test
=== Labeled file widget.
--- wikitext
"File Foo"{file: foo.txt}

=== Labeled link widget.
--- wikitext
"Link Foo"{link: foo}

=== Labeled image widget.
--- wikitext
"Image Foo"{image: foo.jpg}

=== Labeled tag widget.
--- wikitext
"Tag Foo"{tag: foo}

=== Labeled weblog widget.
--- wikitext
"Weblog Foo"{weblog: foo}

*/

