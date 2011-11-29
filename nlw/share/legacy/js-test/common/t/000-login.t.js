(function() {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.login({}, t.nextStep());
    },

    function() {
        t.pass('Logged in...');
        t.endAsync();
    }
]);

})();
