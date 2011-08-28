(function($) {

var t = tt = new Test.SocialCalc();

t.plan(17);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 text t test"),

    function() {
        t.ss.editor.RangeAnchor();
        t.ss.editor.RangeExtend('B2');
        t.click('#move-toggle');
        t.callNextStep();
    },

    t.doClick('#st-filldown-button-link'),
    t.doCheckText('test', 'Fill Down', 'A2'),
    t.doClick('#st-fillright-button-link'),
    t.doCheckText('test', 'Fill Right', 'B2'),

    function() {
        t.ss.editor.RangeRemove();
        t.callNextStep();
    },

    t.doClick('#st-insert-row-below-button-link'),
    t.doCheckText('test', 'Insert Row Below', 'A3'),
    t.doClick('#st-insert-row-above-button-link'),
    t.doCheckText('test', 'Insert Row Above', 'A4'),

    t.doClick('#st-insert-col-right-button-link'),
    t.doCheckText('test', 'Insert Col Right', 'C2'),
    t.doClick('#st-insert-col-left-button-link'),
    t.doCheckText('test', 'Insert Col Left', 'D4'),

    t.doClick('#st-move-row-below-button-link'),
    t.doCheckText('test', 'Move Row Down', 'B1'),

    t.doClick('#st-move-row-above-button-link'),
    t.doCheckText('test', 'Move Row Up', 'B2'),

    t.doClick('#st-move-col-right-button-link'),
    t.doCheckText('test', 'Move Col Right', 'A2'),

    t.doClick('#st-move-col-left-button-link'),
    t.doCheckText('test', 'Move Col Left', 'B2'),

    t.doClick('#st-delete-row-button-link'),
    t.doCheckText('test', 'Delete Row', 'B1'),

    t.doClick('#st-delete-col-button-link'),
    t.doCheckText('test', 'Delete Col', 'A1'),

    function() {
        t.ss.editor.RangeAnchor();
        t.ss.editor.RangeExtend('B2');
        t.click('#move-toggle');
        t.callNextStep();
    },

    t.doClick('#st-merge-button-link'),
    t.doCheckAttr('colspan', 2, 'Merge Cell (col)'),
    t.doCheckAttr('rowspan', 2, 'Merge Cell (row)'),

    function() {
        t.ss.editor.RangeRemove();
        t.callNextStep();
    },

    t.doClick('#st-merge-button-link'),

    t.doExec("set B2 text t foo"),
    t.doCheckText('foo', 'Unmerge Cell', 'B2'),

    t.doClick('#st-movemark-button-link'),

    function() {
        t.ss.editor.MoveECell('G7');
        t.ok(t.$('#st-movemark-button-link').hasClass('selected'), 'Mark Range');
        t.callNextStep();
    },

    t.doClick('#st-movepaste-button-link'),
    t.doCheckText('test', 'Move Paste', 'G7'),

    function() {
        t.endAsync();
    }
]);

})(jQuery)
