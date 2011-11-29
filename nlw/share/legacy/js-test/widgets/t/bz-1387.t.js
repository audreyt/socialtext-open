(function($) {

var t = new Test.Visual();

t.plan(1);
t.skipAll("{bz: 3113}: The Recent Conversations widget is no more, superceded by Activities.");

t.runAsync([
    function() {
        t.setup_one_widget('Recent Conversations', t.nextStep());
    },

    function() { 
        t.is(
            t.$('.widgetHeaderTitleBox:first span').attr('title'),
            'Recent Conversations',
            'Header text should hover as titletext'
        );

        t.endAsync();
    }
], 600000);

})(jQuery);
