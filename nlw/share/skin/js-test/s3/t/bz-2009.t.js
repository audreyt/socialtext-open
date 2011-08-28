(function($) {

var t = new Test.Visual();

t.plan(2);

var name = t.gensym();

t.runAsync([
    function() {
        t.open_iframe("/admin/?action=new_page", t.nextStep());
    },

    function() {
        t.poll(function(){
            return t.$('#st-newpage-pagename-edit').is(':visible');
        }, t.nextStep(3000));
    },

    t.doWikitextEdit(),

    function() {
        t.$('#st-newpage-pagename-edit').val(name + "< 3 > 2");
        t.$('#wikiwyg_wikitext_textarea').val("Hello World");
        t.callNextStep();
    },

    t.doSavePage(),

    function() {
        t.unlike(
            t.$('#st-page-titletext').text(),
            /gt/,
            "Greater-than sign should not be escaped in page title"
        );

        t.unlike(
            t.$('#st-page-titletext').text(),
            /lt/,
            "Less-than sign should not be escaped in page title"
        );

        t.endAsync();
    }
]);

})(jQuery);
