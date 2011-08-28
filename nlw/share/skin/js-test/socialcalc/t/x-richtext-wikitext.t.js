(function($) {

var t = tt = new Test.SocialCalc();

t.plan(9);
t.checkRichTextSupport();

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec('set A1 text t {image\\c foo.jpg}'),
    t.doClick('#st-rich-text-button-link'),

    function() {
        t.ok(t.$('#formularFrame').is(':visible'), 'Make an image WAFL. Make the cell rich text. See image?');
        t.is(t.$('#te_inputecho img').size(), 1, '...See image in input focus?');
        t.ss.editor.MoveECell('B1');
        t.ss.editor.MoveECell('A1');

        t.is(t.$('#st-spreadsheet-edit #e-cell_A1 img').size(), 1, 'Move the cursor away. Now put it back. See image in cell?');
        t.callNextStep();
    },

    t.doClick('#st-wiki-text-button-link'),

    function() {
        t.is(t.$('#st-spreadsheet-edit #e-cell_A1 img').size(), 1, 'Now make it wikitext. See wafl?');
        t.callNextStep();
    },

    t.doClick('#st-copy-button-link'),

    function() {
        t.ss.editor.MoveECell('A2');
        t.callNextStep();
    },

    t.doClick('#st-paste-button-link'),

    function() {
        t.is(t.$('#st-spreadsheet-edit #e-cell_A2 img').size(), 1, 'Copy/paste cell to next row down. See wafl?');
        t.callNextStep();
    },

    t.doClick('#st-rich-text-button-link'),

    function() {
        t.ok(t.$('#formularFrame').is(':visible'), 'Make cell rich text. See image?');
        t.callNextStep();
    },

    t.doClick('#st-copy-button-link'),

    function() {
        t.ss.editor.MoveECell('A3');
        t.callNextStep();
    },

    t.doClick('#st-paste-button-link'),

    function() {
        t.is(t.$('#st-spreadsheet-edit #e-cell_A3 img').size(), 1, 'Copy/paste cell to next row down. See wafl?');
        t.callNextStep();
    },

    t.doExec('set A4 text t _*yoyoyo*_'),

    function() {
        t.ss.editor.MoveECell('A4');
        t.callNextStep();
    },

    t.doClick('#st-rich-text-button-link'),

    function() {
        t.is(t.$('#st-spreadsheet-edit #e-cell_A4 i b').size(), 1, 'Type _*yoyoyo*_ into another cell. Click on rich text. See bold, italic?');
        t.ss.editor.MoveECell('B4');
        t.ss.editor.MoveECell('A4');
        t.is(t.$('#st-spreadsheet-edit #e-cell_A4 i b').size(), 1, 'Move cell to right. Move cell back. See bold, italic?');
        t.endAsync();
    }
]);

})(jQuery)
