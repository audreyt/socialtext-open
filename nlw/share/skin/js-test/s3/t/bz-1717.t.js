(function($) {

var t = new Test.Visual();

t.plan(1);

var editableDivCount;

t.runAsync([
    t.doCreatePage(),
    t.doRichtextEdit(),

    function() { 
        editableDivCount = $(
            t.$('#st-page-editing-wysiwyg').get(0)
             .contentWindow.document.documentElement
        ).find('#wysiwyg-editable-div').length;

        t.$('#wikiwyg_button_table').click();
        t.callNextStep(4000);
    },

    function() { 
        t.$('.table-create a.save').click();

        t.poll(function() {
            return ($(
                t.$('#st-page-editing-wysiwyg').get(0)
                 .contentWindow.document.documentElement
            ).find('body table tbody').length > 0)
        }, function() {t.callNextStep();});
    },

    function() { 
        t.is(
            $(
                t.$('#st-page-editing-wysiwyg').get(0)
                 .contentWindow.document.documentElement
            ).find('#wysiwyg-editable-div').length,
            editableDivCount,
            "Inserting a table should result in random editable divs"
        );

        t.endAsync();
    }
]);

})(jQuery);
