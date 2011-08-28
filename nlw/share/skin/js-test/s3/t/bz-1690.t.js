var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage(
        ".html\n"
      + "foo\n"
      + ".html\n"
      + "\n"
      + "bar\n"
    ),
    t.doRichtextEdit(),
    t.doWikitextEdit(),

    function() { 
        t.like(
            t.$('#wikiwyg_wikitext_textarea').val(),
            /^\.html\nfoo\n\.html\n+bar/,
            "Wikitext mode should not cripple .html widgets"
        );

        t.endAsync();
    }
]);
