var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(1);

t.run_is('html', 'text');

/* Test
=== Spaces around links when surrounded by word characters
--- html
<P>I've been<IMG title="Link to file 'babel.rtf'. Click to edit." src="http://topaz.socialtext.net:22021/static/3.1.3.0/widgets/73f0693b8e1d7ce740992bc17ad5d313.png" alt="st-widget-{file: babel.rtf}" />to paradise</P>
--- text
I've been {file: babel.rtf} to paradise

*/
