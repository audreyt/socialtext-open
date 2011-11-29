(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?action=recent_changes", t.nextStep());
    },

    function() {
        t.scrollTo(200);

        var $avatar = t.$("#st-listview-form tr.oddRow td:eq(1) img.avatar");
        t.ok(
            ($avatar.size() >= 1),
            "There are at lease one user avatar in recent changes listview"
        );

    // TODO Need to get this one to pass in the Harness:
    //
        t.is_no_harness(
            t.$.curCSS( $avatar.get(0), "float"),
            "none",
            "Make sure it's not floated to left or right."
        );

        t.endAsync();
    }
]);

})(jQuery);
