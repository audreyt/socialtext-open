var t = new Test.Wikiwyg();

t.plan(2);
t.run_roundtrip('input', 'output');

/* Test
=== Inline WAFL blocks should add extra vertical whitespace around it
--- input
top line

middle {search: foo} line

bottom line

--- output
top line

middle

{search: foo}

line

bottom line

=== After adding vertical whitespace, it should roundtrip correctly
--- input
top line

middle

{search: foo}

line

bottom line

--- output
top line

middle

{search: foo}

line

bottom line

*/
