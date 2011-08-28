(function($) {

var t = new Test.Visual();

t.plan(1);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

t.runAsync([
    function() {
        t.setup_one_widget(
            {
                name: 'Workspace Tags',
                noPoll: true
            },
            t.nextStep()
        );
    },

    function(widget) {
        t.scrollTo(150);
        t.$('a.settings').click();
        t.$('div.widgetContent input.workspace_setting').val(
            "VeryLongNameVeryLongNameVeryLongNameVeryLongName" +
            "VeryLongNameVeryLongNameVeryLongNameVeryLongName" +
            "VeryLongNameVeryLongNameVeryLongNameVeryLongName" +
            "VeryLongNameVeryLongNameVeryLongNameVeryLongName"
        );
        t.ok(
            (t.$('ul#col0').width() >= t.$('div.widgetContent select').width()),
            "Long workspace names should not cause overflow"
        );

        t.endAsync();
    }
], 600000);

})(jQuery);
