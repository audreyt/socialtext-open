(function($) {

var t = tt = new Test.SocialCalc();

t.plan(3);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 text t test"),

    function() {
        t.click('#st-revisions-mode-button-link');
        t.callNextStepOn('#st-spreadsheet-preview td:first');
    },

    function() {
        t.is(t.$('#st-spreadsheet-preview td:first').text(), 'test', 'Revision');
        t.ok(t.$('#st-save-revision-button-link'), 'Restore Revision (disabled for new spreadsheets)');
        t.ok(t.$('#st-edit-revision-button-link'), 'Edit Revision (disabled for new spreadsheets)');
        t.endAsync();
    }
]);

})(jQuery)
