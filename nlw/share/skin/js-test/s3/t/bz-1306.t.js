(function($) {

var t = new Test.Visual();

t.plan(1);

var iframeHeight;

t.runAsync([
    function() {
        t.open_iframe( "/admin/index.cgi?admin_wiki", t.nextStep() );
    },
            
    function() { 
        t.ok(
            t.$('#st-actions-bar:visible').length,
            "ST Actions bar is visible in S3 skin"
        );
        t.endAsync();
    }
]);

})(jQuery);
