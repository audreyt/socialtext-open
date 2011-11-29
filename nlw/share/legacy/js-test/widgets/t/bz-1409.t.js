(function($) {

var t = new Test.Visual();

t.plan(1);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

t.runAsync([
    function() {
        $.ajax({
            url: "/data/workspaces/help-en/pages/socialtext_releases_simple_editing/tags/測",
            type: 'PUT',
            data: {},
            async: false,
            cache: false
        });

        t.setup_one_widget('Workspace Tags', t.nextStep());
    },

    function(widget) {
        t.scrollTo(150);

        setTimeout(function(){
            var found = false;
            widget.$('a').each(function(){
                if ($(this).text().match(/測/)) {
                    found = true;
                }
            });

            t.ok(
                found,
                "Unicode tag names are handled properly"
            );

            t.endAsync();
        }, 2500);
    }
], 600000);

})(jQuery);
