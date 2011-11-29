(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep(3000));
    },
            
    function() { 
        t.$('#st-comment-button-link').click();
        t.callNextStep(3000);
    },
            
    function() { 
        var buttons = t.$('div.comment div.toolbar img.comment_button');
        t.ok(buttons.length, 'We see comment buttons');

        var buttonsWithTitles = t.$('div.comment div.toolbar img.comment_button[title]');
        t.is(buttons.length, buttonsWithTitles.length, 'All comment buttons have titles');

        t.endAsync();
    }
]);

})(jQuery);
