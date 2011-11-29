(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe(
            "/admin/index.cgi?how_do_i_make_a_new_page",
            t.nextStep()
        );
    },

    function() {
        t.poll(function(){
            return(t.$('#st-attachment-listing') && t.$('#st-attachment-listing').length > 0)
        }, t.nextStep());
    },

    function() {
        // Scroll to wherever the attachment widget is
        t.scrollTo(t.$("#st-attachment-listing").offset().top - 50);

        var hoverText = t.$("#st-attachment-listing li:first div.fileInfo").text();
        t.like(hoverText, /\d+\s+at\s+[\d\D]+\s+by\s+[\d\D]+/, "Attachment fileinfo div contains uploader and date info.");

        t.endAsync();
    }
]);

})(jQuery);
