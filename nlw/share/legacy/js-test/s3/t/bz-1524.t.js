(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/", t.nextStep());
    },
            
    function() { 
        t.like(
            t.$('#pageAttribution').text(),
            /views/,
            "update-attribution contains 'x views' info"
        );

        t.endAsync();
    }
]);

})(jQuery);
