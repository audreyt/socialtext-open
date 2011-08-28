(function() {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },

    function() {
        t.$('#st-create-content-link').click();
        t.callNextStep(3000);
    },

    function() {
        t.ok(
            t.$("#spreadsheet-radio").length,
            'SocialCalc is enabled for the admin workspace - NOTE: Please run "st-socialcalc enable" BEFORE running socialcalc tests!'
        );

        t.endAsync();
    }
]);

})();
