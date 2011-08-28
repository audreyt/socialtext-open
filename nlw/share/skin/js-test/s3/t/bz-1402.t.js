(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },
            
    function() { 
        t.$('div#globalNav ul.st-wiki-nav-actions li:first b:first')
         .text("Long Name That Should Cause Line Wrap");
        t.callNextStep(1000);
    },

    function() { 
        var bottom = t.$('#st-search-submit').offset().top
                   + t.$('#st-search-submit').height();

        var top = t.$('#mainNav').offset().top;
        t.isnt(
            bottom, top,
            "Search bar should not overlap with main navigation"
        );

        t.endAsync();
    }
]);

})(jQuery);
