(function($) {

var t = new Test.Visual();

t.plan(1);

t.checkRichTextSupport();

t.runAsync([
    function() {
        t.open_iframe(
            "/admin/index.cgi?action=weblog_display;category=bz_1338_really_long_"
                + t.gensym() + t.gensym() + t.gensym() + t.gensym()
                + t.gensym() + t.gensym() + t.gensym() + t.gensym(),
            t.nextStep()
        );
    },
            
    function() { 
        t.is(
            t.$('#st-editing-tools-edit').offset().top,
            t.$('#controlsRight').offset().top,
            "Overlong weblog names should truncate, not skewing controlsRight display"
        );
        t.endAsync();
    }
]);

})(jQuery);
