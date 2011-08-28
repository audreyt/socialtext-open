var t = new Test.Wikiwyg();

t.filters({
    text: ['wikitext_to_html_js']
});

t.plan(12);

t.run_like('text', 'html');

/*
=== Huggy begin-phrase dash markers should have effect.
--- text
mmm -2 degrees between today- tomorrow

--- html
<p>mmm <del>2 degrees between today</del> tomorrow</p>

=== Huggy begin-phrase dash markers should have effect around WAFLs.
--- text
mmm -{date: 2010-09-15 10:36:30 GMT}- tomorrow

--- html
<p>mmm <del><img[^>]*></del> tomorrow</p>

=== Non-huggy begin-phrase dash markers should have no effect.
--- text
mmm - 2 degrees between today- tomorrow

--- html
<p>mmm - 2 degrees between today- tomorrow</p>

=== Non-huggy end-phrase dash markers should have no effect.
--- text
mmm -2 degrees between today - tomorrow

--- html
<p>mmm -2 degrees between today - tomorrow</p>

=== Huggy begin-phrase asterisk markers should have effect.
--- text
mmm *2 degrees between today* tomorrow

--- html
<p>mmm <b>2 degrees between today</b> tomorrow</p>

=== Huggy begin-phrase dash markers should have effect around WAFLs.
--- text
mmm *{date: 2010-09-15 10:36:30 GMT}* tomorrow

--- html
<p>mmm <b><img[^>]*></b> tomorrow</p>

=== Non-huggy begin-phrase asterisk markers should have no effect.
--- text
mmm * 2 degrees between today* tomorrow

--- html
<p>mmm \* 2 degrees between today\* tomorrow</p>

=== Non-huggy end-phrase asterisk markers should have no effect.
--- text
mmm *2 degrees between today * tomorrow

--- html
<p>mmm \*2 degrees between today \* tomorrow</p>

=== Huggy begin-phrase underscore markers should have effect.
--- text
mmm _2 degrees between today_ tomorrow

--- html
<p>mmm <i>2 degrees between today</i> tomorrow</p>

=== Huggy begin-phrase dash markers should have effect around WAFLs.
--- text
mmm _{date: 2010-09-15 10:36:30 GMT}_ tomorrow

--- html
<p>mmm <i><img[^>]*></i> tomorrow</p>

=== Non-huggy begin-phrase underscore markers should have no effect.
--- text
mmm _ 2 degrees between today_ tomorrow

--- html
<p>mmm _ 2 degrees between today_ tomorrow</p>

=== Non-huggy end-phrase underscore markers should have no effect.
--- text
mmm _2 degrees between today _ tomorrow

--- html
<p>mmm _2 degrees between today _ tomorrow</p>
*/
