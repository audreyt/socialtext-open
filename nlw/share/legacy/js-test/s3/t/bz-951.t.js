var t = new Test.Visual();

t.plan(2);

t.runAsync([
    function() {
        t.put_page({
            workspace: "admin",
            page_name: "Navigation for: Recent Changes",
            content: "*strong*\n_italic_\n",
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe("/admin/index.cgi?action=weblog_display&limit=1&category=Recent+Changes", t.nextStep());
    },

    function() {
        t.scrollTo(200);
        var fontWeight = t.$(".widget div.wiki strong").css("font-weight");
        t.ok_no_harness(
            ((fontWeight == "bold") || (fontWeight == 700)),
            "*strong* is strong"
        );

        t.is_no_harness(
            t.$(".widget div.wiki em").css("font-style"),
            "italic",
            "_italic_ is italic"
        );
        t.endAsync();
    }
]);
