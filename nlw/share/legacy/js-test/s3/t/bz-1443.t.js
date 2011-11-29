var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.put_page({
            workspace: 'admin',
            page_name: "bz_1443",
            content: "bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443.bz_1443",
            callback: t.nextStep()
        });
    },

    function() {
        t.open_iframe("/admin/index.cgi?action=search&scope=_&search_term=bz_1443", t.nextStep());
    },
            
    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.ok(
            t.$('table.dataTable').width() < t.$('#contentContainer').width(),
            "Long contents in search results should be truncated automatically"
        );

        t.endAsync();
    }
]);
