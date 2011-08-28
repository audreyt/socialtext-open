(function($) {

var t = tt = new Test.SocialCalc();

t.plan(9);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    t.doExec("set A1 text t test"),
    t.doClick('#st-undo-button-link'),
    t.doCheckText('', 'Undo'),
    t.doClick('#st-redo-button-link'),
    t.doCheckText('test', 'Redo'),
    t.doClick('#st-cut-button-link'),
    t.doCheckText('', 'Cut'),
    t.doClick('#st-paste-button-link'),
    t.doCheckText('test', 'Paste (from Cut)'),
    t.doClick('#st-copy-button-link'),
    t.doCheckText('test', 'Copy'),
    t.doClick('#st-erase-button-link'),
    t.doCheckText('', 'Erase'),
    t.doClick('#st-paste-button-link'),
    t.doCheckText('test', 'Paste (from Copy)'),
    t.doClick('#st-upload-button-link'),

    function() {
        t.callNextStepOn('#st-attachments-attachinterface');
    },

    function() {
        t.pass('Add File');
        t.click('#st-attachments-attach-closebutton');
        t.callNextStepOn('#st-attachments-attachinterface', ':hidden');
    },

    t.doClick('#st-tag-button-link'),

    function() {
        t.callNextStepOn('#st-tagqueue-interface');
    },

    function() {
        t.pass('Add Tag');
        t.click('#st-tagqueue-close');
        t.callNextStep(1000);
    },

    function() {
        t.endAsync();
    }
]);

})(jQuery)
