(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    t.doCreatePage("Test\n", {w: 1024}),

    function() { 
        t.win.Cookie.del("ui_is_expanded");
        t.callNextStep();
    },

    t.doRichtextEdit(),

    function() { 
        t.$('#st-edit-pagetools-expand').click();

        var $editArea = t.$('iframe#st-page-editing-wysiwyg');
        t.ok(
            ($editArea.offset().left + $editArea.width())
                < (t.$('#st-edit-mode-view').offset().left + t.$('#st-edit-mode-view').width()),
            "Edit area's right edge does not go beyond the page"
        );

        t.callNextStep();
    },

    t.doSavePage(),

    t.doCreatePage("Test\n", {w: 1024}),
    t.doRichtextEdit(),

    function() { 
        var $editArea = t.$('iframe#st-page-editing-wysiwyg');
        t.ok(
            ($editArea.offset().left + $editArea.width())
                < (t.$('#st-edit-mode-view').offset().left + t.$('#st-edit-mode-view').width()),
            "Edit area's right edge does not go beyond the page"
        );

        t.win.Cookie.del("ui_is_expanded");
        t.endAsync();
    }
]);

})(jQuery);
