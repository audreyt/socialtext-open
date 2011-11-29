var t = new Test.Visual();

t.plan(1);

var name = "bz_1262_really_long_"
    + t.gensym() + t.gensym() + t.gensym() + t.gensym()
    + t.gensym() + t.gensym() + t.gensym() + t.gensym();

t.runAsync([
    function() {
        t.put_page({
            workspace: 'admin',
            page_name: name,
            content: name,
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe(
            "/admin/?" + name,
            t.doRichtextEdit()
        );
    },
            
    function() { 
        t.elements_do_not_overlap(
            t.$('#st-editing-title'),
            t.$('#st-edit-mode-toolbar'),
            "Overlong page names should truncate, not overlapping edit toolbar"
        );
        t.endAsync();
    }
]);
