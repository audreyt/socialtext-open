(function($) {

var t = new Test.Visual();

t.plan(5);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },

    function() {
        t.scrollTo(100);

        t.ok(
            t.$("div#st-display-mode-container").is(":visible"),
            'Display is visible before edit'
        );

        t.ok(
            t.$("div#st-edit-mode-view").is(":hidden") ||
            ( t.$("div#st-edit-mode-view").size() == 0 ),
            'Editor is not visible'
        );

        t.$("#bottomButtons a.editButton").click();

        t.callNextStep(3000);
    },

    function() {
        t.ok(
            t.iframe.contentWindow.Wikiwyg,
            'click starts wikiwyg'
        );
        t.ok(
            t.$("div#st-display-mode-container").is(":hidden"),
            'Display is hidden after clicking edit button'
        );

        t.ok(
            t.$("div#st-edit-mode-view").is(":visible"),
            'Editor is now visible'
        );

        t.$("#st-editing-tools-edit a.saveButton").click();

        t.callNextStep(3000);

    },

    function() {
        t.endAsync();
    }
]);

})(jQuery);
