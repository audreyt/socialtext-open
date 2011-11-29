(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.open_iframe(
            "/admin/index.cgi?action=weblog_display&category=TEST" +
                t.gensym(),
            t.nextStep()
        );
    },

    function() {
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.elements_do_not_overlap(
            t.$('#st-weblog-newpost-button'),
            t.$('#page-control-category-selector'),
            "In weblog view, page navs shouldn't overlap on each other"
        );

        t.elements_do_not_overlap(
            t.$('#st-weblog-newpost-button'),
            t.$('#contentRight'),
            "Also page navs shouldn't overlap with the right-side content pane"
            + " (bugs.socialtext.net:555/attachment.cgi?id=87)"
        );
        t.endAsync();
    }
])

})(jQuery);
