(function($) {

var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?action=recent_changes", t.nextStep());
    },

    function() {
        t.scrollTo(300);

        t.like(
            t.$("table.dataTable tr.oddRow td span.revision-count a:eq(0)").attr("href"),
            /action=revision_list;page_name=/,
            "Revision links in listview need to href to revision_list action"
        );

        t.endAsync();
    }
]);

})(jQuery);
