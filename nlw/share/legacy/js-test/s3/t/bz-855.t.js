(function($) {

var t = new Test.Visual();

t.plan(2);

if (jQuery.browser.msie)
    t.skipAll("{bz: 855} isa bug on Mozilla browsers. On IE, those two elements are not overlapping but still look bad in other ways.");

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?action=recent_changes", t.nextStep());
    },

    function() {
        $(t.iframe).height(200);
        var widths = [1100, 800];
        for (var i = 0, l = widths.length; i < l; i++) {
            var width = widths[i];
            $(t.iframe).width(width);

            t.elements_do_not_overlap(
                'div.tableFilter ul',
                'div#controlsRight',
                'Export and Tools do not overlap when window width is ' + width
            );

            t.scrollTo(50, width);
        }

        t.endAsync();
    }
]);

})(jQuery);
