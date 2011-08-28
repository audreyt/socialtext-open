(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/st/dashboard?gallery=1", t.nextStep(), {w: 640});
    },
            
    function() { 
        t.scrollTo(
            t.$('#controlsRight').offset().top
        );

        t.is(
            t.$('#st-editing-tools-edit').offset().top,
            t.$('#controlsRight').offset().top,
            "Narrow screen should not cause gallery's controlsRight to drop"
        );

        t.endAsync();
    }
]);

})(jQuery);
