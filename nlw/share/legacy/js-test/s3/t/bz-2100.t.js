(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    t.doCreatePage('Test'),
    t.doRichtextEdit(),

    function() { 
        t.$('#st-edit-mode-tagbutton').click();
        t.$('#st-tagqueue-field').val('double " quote');
        t.$('#st-tagqueue').submit();
        t.$('#st-tagqueue-field').val('left < caret');
        t.$('#st-tagqueue').submit();
        t.$('#st-tagqueue-close').click();
        t.callNextStep();
    },

    t.doSavePage(),

    function() { 
        var texts = [
            t.$('a.tag_name:first').text(),
            t.$('a.tag_name:last').text()
        ].sort();

        t.is(
            texts[0],
            'double " quote',
            "Double quote works when added as a tag in rich text mode"
        );

        t.is(
            texts[1],
            'left < caret',
            "Left caret works when added as a tag in rich text mode"
        );

        t.endAsync();
    }
]);

})(jQuery);
