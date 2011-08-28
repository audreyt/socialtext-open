(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage('{{ "x" }}'),
    t.doWikitextEdit(),
    t.doRichtextEdit(),
    t.doWikitextEdit(),

    function() { 
        t.unlike(
            t.$('#wikiwyg_wikitext_textarea').val(),
            /quot/,
            "Roundtripping mode should not cripple as-is sections"
        );

        t.endAsync();
    }
]);

})(jQuery);
