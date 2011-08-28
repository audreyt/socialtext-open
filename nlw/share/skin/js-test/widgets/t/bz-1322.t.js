(function($) {

var t = new Test.Visual();

t.plan(1);
t.skipAll("{bz: 3113}: The Recent Conversations widget is no more, superceded by Activities.");

t.runAsync([
    function() {
        $.ajax({
            url: "/?action=clear_widgets",
            async: false
        });
        $.ajax({
            url: "/?action=add_widget;type=dashboard;src=file:widgets/share/widgets/recent_conversations.xml",
            async: false
        });
        t.open_iframe("/", t.nextStep(), {w: 600});
    },
            
    function() { 
        var headerTop = t.$('.widgetHeader').offset().top;
        var titleTop  = t.$('.widgetHeaderTitleBox').offset().top;

        t.ok(
            ((titleTop - headerTop) < 10),
            'Header text should not drop when oversized'
        );

        t.endAsync();
    }
], 600000);

})(jQuery);
