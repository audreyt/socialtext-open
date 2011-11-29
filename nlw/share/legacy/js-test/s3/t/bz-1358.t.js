(function($) {

var t = new Test.Visual();

t.plan(1);

t.checkRichTextSupport();

var iframeHeight;

t.runAsync([
    function() {
        t.open_iframe(
            "/admin/index.cgi?bz_1358_" + t.gensym(),
            t.nextStep(5000),
            { h: '600px' }
        );
    },
            
    function() { 
        iframeHeight = t.$('#st-page-editing-wysiwyg').height();

        t.$('#st-preview-button-link').click();
        t.callNextStep(2500);
    },

    function() { 
        t.$('#st-preview-button-link').click();
        t.callNextStep(2500);
    },

    function() { 
        t.is(
            iframeHeight,
            t.$('#st-page-editing-wysiwyg').height(),
            "iframe height stays the same after roundtripping through Preview"
        );

        t.endAsync();
    }
]);

})(jQuery);
