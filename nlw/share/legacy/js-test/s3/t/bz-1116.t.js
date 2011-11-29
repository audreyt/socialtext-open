(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage("test\n"),
    t.doWikitextEdit(),

    function() { 
        t.win.wikiwyg.current_mode.insert_widget('{file: bz_1116}');
        t.like(
            t.$('#wikiwyg_wikitext_textarea').val(),
            /^\{file: bz_1116\}\s+test/
        );
        t.endAsync();
    }
]);

})(jQuery);
