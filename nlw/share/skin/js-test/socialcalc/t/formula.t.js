(function($) {

var t = tt = new Test.SocialCalc();

t.plan(4);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 value n 1"),
    t.doExec("set A2 value n 2"),
    t.doExec("set A3 value n 3"),

    function() {
        t.ss.editor.RangeAnchor();
        t.ss.editor.RangeExtend('A3');
        t.click('#st-sum-range-button-link');
        t.ss.editor.RangeRemove();
        t.ss.editor.MoveECell('B1');
        t.click('#st-multiline-button-link');
        t.click('#st-multiline-button-link');
        t.is(t.$('#wikiwyg_wikitext_textarea').height(), 64, 'Multi-line Input');
        t.ok(t.$('#st-apply-button-link').is(':visible'), 'Multi-line Apply');
        t.click('#st-apply-button-link');
        t.callNextStepOnReady();
    },

    t.doCheckText('6', 'Quick Sum', 'A4'),

    function() {
        t.click('#st-edit-mode-button-link');
        t.click('#st-oneline-button-link');
        t.is(t.$('#wikiwyg_wikitext_textarea').height(), 18, 'Single-line Input');
        t.endAsync();
    }
]);

})(jQuery)
