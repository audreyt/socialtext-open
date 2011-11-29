(function($) {

var t = new Test.Visual();

t.plan(1);

if (jQuery.browser.msie)
    t.skipAll("We check for .designMode in Mozilla only as IE doesn't allow querying this attribute.");

t.runAsync([
    t.doCreatePage("Some text\n"),
    t.doWikitextEdit(),
    t.doRichtextEdit(),

    function() { 
        t.is(
            t.$('#st-page-editing-wysiwyg').get(0).contentWindow.document.designMode,
            'on',
            'Rich text edit area is user-editable'
        );

        t.endAsync();
    }
]);

})(jQuery);
