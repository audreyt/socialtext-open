(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?advanced_getting_around", t.nextStep());
    },
            
    function() { 
        t.scrollTo(
            t.$('#st-tags-listing').offset().top
        );

        t.$('#st-tags-listing li:first a:first').text(
            'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
            'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
            'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
            'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
            'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        );

        t.is(
            t.$('#st-tags-listing li:first a:first').css('overflow'),
            'hidden',
            "Overlong tag names should not overflow visibly"
        );

        t.endAsync();
    }
]);

})(jQuery);
