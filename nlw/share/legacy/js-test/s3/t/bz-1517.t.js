var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/?action=new_page", t.nextStep());
    },
            
    function() { 
        t.poll(function(){
            return t.$('#st-newpage-pagename-edit').is(':visible');
        }, t.nextStep(3000));
    },

    function() { 
        t.$('#st-save-button-link').click();
        t.poll(function(){
            return t.$('#st-newpage-save-pagename').is(':visible');
        }, t.nextStep(3000));
    },

    function() { 
        if (t.doc && t.doc.activeElement) {
            t.is(
                t.doc.activeElement.getAttribute('id'),
                'st-newpage-save-pagename',
                "st-newpage-save-pagename received focus correctly"
            );
        }
        else {
            t.skip("This browser has no activeElement support");
        }

        t.$('#st-newpage-save-cancelbutton').click();
        t.$('#st-newpage-pagename-edit').val(t.gensym());

        t.endAsync();
    }
]);
