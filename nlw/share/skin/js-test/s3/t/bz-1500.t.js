(function($) {

var t = new Test.Visual();

var tests = [];
var pages = ['/nlw/login.html', '/nlw/register.html', '/nlw/forgot_password.html'];

for (var idx in pages) {
    // Can't say "var url = pages[idx]" here because JS loops doesn't renew the pad
    (function(url){
        tests.push(function() {
            t.open_iframe(url, t.nextStep());
        });
        tests.push(function() {
            t.ok(
                t.$('.authentication #controls').length,
                url + " is styled correctly"
            );
            t.callNextStep();
        });
    })(pages[idx]);
}

tests.push(function(){
    t.endAsync();
});

t.plan(pages.length);
t.runAsync(tests);

})(jQuery);
