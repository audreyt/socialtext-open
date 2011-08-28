var t = new Test.Visual();

t.plan(1);

var original = t.gensym();
var incipient = t.gensym();

t.runAsync([
    function() {
        t.put_page({
            workspace: 'admin',
            page_name: original,
            content: "{include: [" + incipient + "]}\n",
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe(
            "/m/page/admin/" + original,
            t.nextStep()
        );
    },

    function() { 
        t.like(
            $('a.smallEditButton', t.doc).attr('href'),
            /\/m\//,
            "The edit link goes to /m/ when viewed inside /m/"
        );

        t.endAsync();
    }
]);
