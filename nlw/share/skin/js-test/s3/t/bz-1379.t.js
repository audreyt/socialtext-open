(function($) {

var t = new Test.Visual();

t.plan(3);

t.runAsync([
    function() {
        t.open_iframe( "/nlw/login.html", t.nextStep() );
    },
            
    function() { 
        var u = t.$('#username');
        var p = t.$('#password');
        t.ok(u.length, "There is a #username field");
        t.ok(p.length, "There is a #password field");
        if (t.doc && t.doc.activeElement) {
            t.ok(
                ((t.doc.activeElement == u.get(0))
                    || (t.doc.activeElement == p.get(0))),
                "Input is focused on #username or #password"
            );
        }
        else {
            t.skip("t.doc.activeElement() is not exposed by the browser");
        }
        t.endAsync();
    }
]);

})(jQuery);
