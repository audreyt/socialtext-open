(function($) {

var t = new Test.Visual();

t.plan(3);

var iframeHeight;

t.runAsync([
    function() {
        t.open_iframe( "/admin/index.cgi?admin_wiki", t.nextStep() );
    },
            
    function() { 
        t.$('#st-pagetools-email').click();
        t.callNextStep(1500);
    },

    function() { 
        t.is(
            t.$('#lightbox').css('overflow'),
            'auto',
            'Lightbox overflows when the page height is insufficient'
        );
        t.$('#email-cancel').click();
        t.callNextStep(1500);
    },

    function() { 
        $(t.iframe).css('height', '768px');
        t.callNextStep(1500);
    },

    function() { 
        t.$('#st-pagetools-email').click();
        t.callNextStep(1500);
    },

    function() { 
        t.is(
            t.$('#lightbox').css('overflow'),
            'hidden',
            'Lightbox does not overflow when the page height is sufficient'
        );
        t.$('#email-cancel').click();
        t.callNextStep(1500);
    },

    function() { 
        $(t.iframe).css('height', 200);
        t.$('#st-pagetools-email').click();
        t.callNextStep(1500);
    },

    function() { 
        t.is(
            t.$('#lightbox').css('overflow'),
            'auto',
            'Lightbox overflows when the page height is insufficient (again)'
        );
        t.$('#email-cancel').click();

        t.endAsync();
    }
]);

})(jQuery);
