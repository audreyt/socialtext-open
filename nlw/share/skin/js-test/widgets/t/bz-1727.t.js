(function($) {

var t = new Test.Visual();

t.plan(1);

t.skipAll("{bz: 3113}: NOTE: ToDo widget has changed recently, and is <snip> unworthy of testing.");

t.runAsync([
    function() {
        t.setup_one_widget(
            {
                name: 'LabPixies ToDo',
                noPoll: true
            },
            t.nextStep()
        );
    },

    function(widget) {
        t.like(
            widget.$('body').html(),
            /Type new task here/,
            "TODO widget initialized correctly"
        );

        t.endAsync();
    }
], 600000);

})(jQuery);
