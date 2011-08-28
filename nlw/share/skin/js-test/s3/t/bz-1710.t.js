var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage(
        ".html\n" +
        "X&nbsp;Y\n" +
        ".html\n"
    ),
    t.doRichtextEdit(),
    t.doWikitextEdit(),

    function() { 
        t.unlike(
            t.$('#wikiwyg_wikitext_textarea').val(),
            /XnbspY/,
            "Wikitext mode should not cripple ampersand and semicolons in .html widgets"
        );

        t.endAsync();
    }
]);
