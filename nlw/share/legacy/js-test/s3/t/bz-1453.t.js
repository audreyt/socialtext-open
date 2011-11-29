var t = new Test.Visual();

t.plan(3);

var name = "bz_1453_" + t.gensym();

t.runAsync([
    function() {
        t.put_page({
            workspace: 'admin',
            page_name: name,
            content: "[bz_1453_incipient_"+t.gensym()+"]",
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe("/admin/?" + name, t.nextStep());
    },
            
    function() { 
        t.is(
            t.$('div.wiki a.incipient').length, 1,
            'Incipient link is rendered with class="incipient"'
        );

        t.open_iframe(
            t.$('div.wiki a.incipient').get(0).href,
            t.nextStep(3000)
        );
    },

    function() { 
        t.is(
            t.$('#st-newpage-pagename-edit:visible').length, 0,
            'Incipient editing title does not have a visible input box'
        );

        t.is(
            t.$('#st-newpage-pagename-edit').length, 1,
            'Incipient editing title does have an invisible input box'
        );

        t.endAsync();
    }
]);
