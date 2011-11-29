(function($) {

var t = new Test.Visual();

t.plan(3);

t.runAsync([
    function() {
        t.open_iframe( "/", t.nextStep() );
    },
            
    function() { 
        var minHeight = 300;
        t.ok(
            t.$('#col0').height() >= minHeight,
            "Left list is at least 300 pixels high"
        );
        t.ok(
            t.$('#col1').height() >= minHeight,
            "Middle list is at least 300 pixels high"
        );
        t.ok(
            t.$('#col2').height() >= minHeight,
            "Right list is at least 300 pixels high"
        );
        t.endAsync();
    }
]);

})(jQuery);
