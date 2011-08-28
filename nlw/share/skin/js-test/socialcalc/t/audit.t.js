(function($) {

var t = tt = new Test.SocialCalc();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 text t test"),

    function() {
        t.click('#st-audit-mode-button-link');
        t.callNextStepOn('#st-spreadsheet-audit');
    },

    function() {
        t.is(t.$('#st-spreadsheet-audit').text(), "Audit Trail For This Session:set A1 text t test");
        t.endAsync();
    }
]);

})(jQuery)
