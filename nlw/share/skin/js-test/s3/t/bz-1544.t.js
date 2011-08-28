var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage(),

    function() { 
        t.$('#st-comment-button-link').click();
        t.poll(function(){
            return t.$('div.comment').is(':visible');
        }, t.nextStep(2000));
    },
            
    function() { 
        if (t.doc && t.doc.activeElement) {
            t.is(
                t.doc.activeElement.tagName.toLowerCase(),
                'textarea',
                "Text area gets focus after the user clicks Comment"
            );
        }
        else {
            t.skip("This browser has no activeElement support");
        }

        t.endAsync();
    }
]);
