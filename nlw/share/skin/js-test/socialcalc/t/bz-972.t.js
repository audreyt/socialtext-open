(function($) {

var t = tt = new Test.SocialCalc();

t.plan(1);

t.runAsync([
    function() {
        t.login({}, t.nextStep());
    },

    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    function() {
        var val = t.callEventHandler("#st-color-button-link", "click");
        t.is(val, false, "Event handler returns false");

        t.endAsync();
    }
]);

})(jQuery);
