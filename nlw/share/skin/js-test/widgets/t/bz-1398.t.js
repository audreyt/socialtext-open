(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([

    function() {
        t.open_iframe("/st/dashboard?gallery=1", t.nextStep());
    },
            
    function() { 
        function bottomOffset$ (sel) {
            var el = t.$(sel);
            return el.offset().top
                 + el.height()
                 + parseInt(el.css('padding-top'))
                 + parseInt(el.css('padding-bottom'));
        }

        t.is(
            bottomOffset$('#controls'),
            t.$('#contentContainer').offset().top,
            "Header and the gallery should be next to each other"
        );

        t.ok(
            (Math.abs(
                bottomOffset$('#contentContainer')
                - t.$('#footer').offset().top
            ) <= 1),
            "Footer and the gallery should be next to each other"
        );
        t.endAsync();
    }
], 600000);

})(jQuery);
