var t = new Test.Visual();

t.plan(1);

var page = t.gensym();

t.runAsync([
    function() {
        t.put_page({
            workspace: 'admin',
            page_name: page,
            content: "^Header\n\none\ntwo\nthree\nfour\n",
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe(
            "/admin/?" + page,
            t.nextStep()
        );
    },

    function() { 
        t.ok(
            (t.$('div.wiki br').length > 1), "Linebreaks should be preserved"
        );

        t.endAsync();
    }
]);
