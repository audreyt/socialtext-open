(function($) {

var t = tt = new Test.SocialCalc();

t.plan(7);

t.runAsync([
    function() {
        t.open_iframe_with_socialcalc("/admin/index.cgi?action=display;page_type=spreadsheet;page_name="+t.gensym()+"#edit", t.nextStep());
    },

    function() {
        t.click('#align-toggle');
        t.callNextStep();
    },

    t.doClick('#st-left-button-link'),
    t.doCheckCSS('text-align', 'left', 'Left'),
    t.doClick('#st-right-button-link'),
    t.doCheckCSS('text-align', 'right', 'Right'),
    t.doClick('#st-center-button-link'),
    t.doCheckCSS('text-align', 'center', 'Center'),
    t.doClick('#st-justify-button-link'),
    t.doCheckCSS('text-align', 'justify', 'Justify'),

    t.doClick('#st-top-button-link'),
    t.doCheckCSS('vertical-align', 'top', 'Top'),
    t.doClick('#st-middle-button-link'),
    t.doCheckCSS('vertical-align', 'middle', 'Middle'),
    t.doClick('#st-bottom-button-link'),
    t.doCheckCSS('vertical-align', 'bottom', 'Bottom'),

    function() {
        t.endAsync();
    }
]);

})(jQuery)
