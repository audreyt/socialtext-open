(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },

    function() {
        t.scrollTo(330);

        t.is(
            t.$("div.widget:eq(1) div.widgetContent p").text(),
            "There are no pages that link to this page yet.",
            "Admin Wiki is an orphan page, should say so"
        );

        t.endAsync();
    }
]);

})(jQuery);
