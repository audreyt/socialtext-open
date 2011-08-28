(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.create_anonymous_user_and_login({workspace: 'admin'}, t.nextStep());
    },

    function() {
        t.open_iframe("/", t.nextStep());
    },

    function step4() {
        $(t.iframe).width(1000);
        t.scrollTo(50);
        var message = t.$("div.welcome").text()
            .replace(/^\s*([\s\S]*?)\s*$/, '$1')
            .replace(/\s+/g, ' ');
        var expected = 'Welcome, New User Please complete your profile now.';
        t.is(message, expected,
            'Message is correct (' + expected + ') when user has no name'
        );
        t.endAsync();
    }
], 600000);

})(jQuery);
