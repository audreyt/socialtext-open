(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },
            
    function() { 
        var listHeight = t.$('div#globalNav ul.st-wiki-nav-actions li:first')
                          .height();
        var textHeight = t.$('div#globalNav ul.st-wiki-nav-actions b:first')
                          .height();

        t.ok(listHeight >= textHeight, "Text should not clip in globalNav");

        t.endAsync();
    }
]);

})(jQuery);
