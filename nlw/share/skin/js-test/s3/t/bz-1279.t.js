(function($) {

var t = new Test.Visual();

t.plan(2);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

t.runAsync([
    function() {
        t.open_iframe("/data/workspaces/admin/attachments/admin_wiki:0-0-0/original/VeryBad", t.nextStep());
        setTimeout(function() {
            if (t.asyncId) {
                t.skipAll('The browser has overridden our own 404 message');
                t.endAsync();
            }
        }, 5000);
    },
            
    function() { 
        try {
            if (t.doc && t.doc.body) {
                t.unlike(
                    t.doc.body.innerHTML,
                    /Carp/,
                    "Invalid attachment URL should not lead to ugly error message"
                );

                t.like(
                    t.doc.body.innerHTML,
                    /VeryBad/,
                    "The error message should contain the attachment file name"
                );
            }
            else {
                t.skipAll('The browser has overridden our own 404 message');
            }
        }
        catch (e) {
            t.skipAll('The browser has overridden our own 404 message');
        }

        t.endAsync();
    }
]);

})(jQuery);
