(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage("|  |\n"),
    t.doWikitextEdit(),
    t.doRichtextEdit(),

    function() { 
        t.poll(function() {
            return ($(
                t.$('#st-page-editing-wysiwyg').get(0)
                 .contentWindow.document.documentElement
            ).find('body table tbody').length > 0)
        }, function() {t.callNextStep();});
    },

    function() { 
        t.$('#wikiwyg_button_add-col-right').click();
        t.callNextStep(1500);
    },

    function() { 
        t.$('#wikiwyg_button_add-col-right').click();
        t.callNextStep(1500);
    },

    function() { 
        t.$('#wikiwyg_button_del-col').click();
        t.callNextStep(1500);
    },

    function() { 
        t.$('#wikiwyg_button_del-col').click();
        t.callNextStep(1500);
    },

    function() { 
        t.is(
            $(
                t.$('#st-page-editing-wysiwyg').get(0)
                 .contentWindow.document.documentElement
            ).find('body table tbody td').length,
            1,
            "1 + 2 - 2 = 1"
        );

        t.endAsync();
    }
]);

})(jQuery);
