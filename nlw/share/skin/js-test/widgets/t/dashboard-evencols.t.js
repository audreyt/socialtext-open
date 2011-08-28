(function($) {

var WIDTH_MIN = 100;
var WIDTH_MAX = 1500;
var WIDTH_INT = 10;

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        $.ajax({
            url: "/?action=clear_widgets",
            async: false
        });

        t.open_iframe("/", t.nextStep());
    },

    function() {
        var always_even = true;
        for (var width = WIDTH_MIN; width <= WIDTH_MAX; width += WIDTH_INT) {
            $(t.iframe).width(width);
            t.scrollTo(t.$('#col0').offset().top, width);

            always_even = ( t.$('#col0').offset().top ==
                            t.$('#col1').offset().top ) &&
                          ( t.$('#col1').offset().top ==
                            t.$('#col2').offset().top );
            if (!always_even) break;
        }

        t.ok(always_even, "Column top is always aligned");

        t.endAsync();
    }
], 600000);

})(jQuery);
