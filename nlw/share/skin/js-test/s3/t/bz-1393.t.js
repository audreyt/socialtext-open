(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/?profile/2", t.nextStep());
    },
            
    function() { 
        var ul  = t.$('div#controlsRight ul.level1');
        t.ok(
            ul.width() <= 300,
            "[Follow this person] is not overly wide"
        );

        t.endAsync();
    }
]);

})(jQuery);
