var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage("^ H1\n\n^^ H2"),
    t.doRichtextEdit(),

    function() { 
        var editArea = $(
            t.$('#st-page-editing-wysiwyg').get(0)
             .contentWindow.document.documentElement
        );
        var $h1 = editArea.find('h1');
        var $h2 = editArea.find('h2');

        t.scrollTo(500);

        t.isnt(
            $h1.height(),
            $h2.height(),
            'Heading styles are in effect for rich text edit'
        );

        t.endAsync();
    }
]);
