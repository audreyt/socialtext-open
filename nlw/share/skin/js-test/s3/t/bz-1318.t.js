(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    t.doCreatePage("{toc}\n"),
    t.doRichtextEdit(),

    function() { 
        var ww = t.iframe.contentWindow.Wikiwyg.Wysiwyg.prototype;
        var img = $(
            t.$('#st-page-editing-wysiwyg').get(0).contentWindow.document.documentElement
        ).find('img').get(0);
        ww.getWidgetInput(img, false, false);

        t.callNextStepOn('#st-widget-cancelbutton');
    },

    function() { 
        t.ok(
            t.$('#st-widget-cancelbutton').is(':visible'),
            "Clicking on the TOC image brings out a wikiwyg widget form"
        );

        t.$('#st-widget-cancelbutton').click();
        t.callNextStep();
    },

    t.doSavePage(),

    function() { 
        t.ok(
            true,
            "Dismissing the TOC image did not raise javascript errors"
        );

        t.endAsync();
    }
]);

})(jQuery);
