(function($) {

var t = new Test.Visual();

t.plan(4);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

t.runAsync([
    function() {
        t.setup_one_widget(
            {
                name: 'Workspaces',
                noPoll: true
            },
            t.nextStep()
        );
    },

    function() {
        t.scrollTo(150);

        t.is(
            t.$('div.widget.minimized').length,
            0,
            "Widgets start off non-minimized"
        );

        t.$('div.widgetHeader a.minimize:first').click();

        t.is(
            t.$('div.widget.minimized').length,
            1,
            "Clicking 'minimize' causes minimization"
        );

        t.callNextStep(5000); // Wait for the POST to go through
    },

    function() {
        t.open_iframe('/', t.nextStep(3000));
    },

    function() {
        t.is(
            t.$('div.widget.minimized').length,
            1,
            "Minimizing a widget should persist across reloads"
        );

        t.$('div.widgetHeader a.minimize:first').click();

        t.is(
            t.$('div.widget.minimized').length,
            0,
            "Clicking 'minimize' again stops minimization"
        );

        t.endAsync();
    }
], 600000);

})(jQuery);
