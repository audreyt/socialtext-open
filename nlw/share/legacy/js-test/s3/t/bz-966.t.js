(function($) {

var t = new Test.Visual();

t.plan(2);

var topOffset;

t.runAsync([
    function() {
        t.open_iframe(
            "/admin/index.cgi?how_do_i_make_a_new_page",
            t.nextStep()
        );
    },
            
    function() {
        // Remember the vertical position of that button
        topOffset = t.$("#bottomButtons .editButton").offset().top;

        // Scroll to wherever the bottom Edit button is
        t.scrollTo(topOffset - 50);

        var imgs = '';
        for (var i = 0 ; i < 40; i++) {
            imgs += '<img src="/static/skin/s3/images/logo.png?_=' + t.gensym() + ' />'
            + '<br /><br /><br /><br /><br />';
        }

        // Now reset the HTML content with the setPageContent method
        t.win.Page.setPageContent(
            '<div>' + imgs + '</div>'
        );

        t.callNextStep(3000);
    },
            
    function() {
        var newOffset = t.$("#bottomButtons .editButton").offset().top;

        // Ensure that it moved after the page content moved
        t.isnt(
            topOffset,
            newOffset,
            'The bottom Edit button moved after the page content moved'
        );

        // Scroll to wherever the bottom Edit button is again
        t.scrollTo(newOffset - 50);

        var pageAttributionOffset = t.$("#pageAttribution").offset().top;

        t.ok(
            (newOffset > pageAttributionOffset),
            'The bottom Edit button stayed after image expansion'
        );

        t.endAsync();
    }
]);

})(jQuery);
