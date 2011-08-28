(function($) {

var t = tt = new Test.SocialCalc();

t.plan(8);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 value n 1234"),

    t.doClick('#st-bold-button-link'),
    t.doCheckCSS('font-weight', 'bold', 'Bold'),
    t.doClick('#st-italic-button-link'),
    t.doCheckCSS('font-style', 'italic', 'Italic'),
//    t.doClick('#st-cell-borders-button-link'),
//    t.doCheckCSS('border-style', 'solid', 'Border On'),
//    t.doClick('#st-cell-borders-button-link'),
//    t.doCheckCSS('border', '', 'Border Off'),

    function() {
        t.$('#st-spreadsheet-cell-font-family').val('Verdana,Arial,Helvetica,sans-serif').change();
        t.$('#st-spreadsheet-cell-font-size').val(28).change();
        t.$('#st-spreadsheet-cell-number-format').val('#,##0').change();
        t.callNextStep();
    },

    t.doClick('#st-color-button-link'),
    t.doClick('#st-color-cc0000'),
    t.doClick('#st-bgcolor-button-link'),
    t.doClick('#st-bgcolor-ff0000'),
    t.doClick('#st-swapcolors-button-link'),

    function() {
        t.click('#st-preview-button-link');
        t.callNextStepOn("#st-spreadsheet-preview td");
    },

    t.doCheckCSS('font-family', 'Verdana,Arial,Helvetica,sans-serif', 'Set Font'),
    t.doCheckCSS('font-size', true, 'Set Size'),
    t.doCheckText('1,234', 'Set Format'),

    function() {
        t.like(t.$("#st-spreadsheet-preview td").css('color').replace(/,\s+/g, ','), /#ff0000|rgb\(255,0,0\)/i, 'Text Color');
        t.like(t.$("#st-spreadsheet-preview td").css('background-color').replace(/,\s+/g, ','), /#cc0000|rgb\(204,0,0\)/i, 'Background Color');
        t.pass('Swap Color'); // Passed implicitly by color/bgcolor above
        t.endAsync();
    }
]);

})(jQuery)
