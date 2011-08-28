(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?action=weblog_display;category=Welcome", t.nextStep());
    },
            
    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.scrollTo(
            t.$('a.weblog_comment:first').offset().top
        );

        var el = t.$('div#contentLeft').get(0);

        t.is(
            el.offsetHeight,
            el.clientHeight,
            "No initial horizontal scrollbar in weblog view"
        );

        t.$('a.weblog_comment:first').click();

        t.callNextStep(1500);

    },

    function() {
        var el = t.$('div#contentLeft').get(0);

        t.is(
            el.offsetHeight,
            el.clientHeight,
            "No initial horizontal scrollbar after clicking comment"
        );

        t.endAsync();
    }
]);

})(jQuery);
