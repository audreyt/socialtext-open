(function($) {

var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.open_iframe("/nlw/submit/logout?redirect_to=/auth-to-edit/", t.nextStep());
    },
            
    function() { 
        t.ok(
            t.$('div#newPageButton').length,
            "A newPageButton div is there even if the user can't edit the page"
        );

        t.ok(
            t.$('div#newPageButton').hasClass('disabled'),
            "That newPageButton div is properly marked as disabled"
        );

        t.login({}, t.nextStep());
    },
            
    function() { 
        t.endAsync();
    }
]);

})(jQuery);
