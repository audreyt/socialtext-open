(function() {

var t = new Test.Performance();

t.plan(8);

t.timedLoad(
    "/data/workspaces/help-en/pages/",
    2000,
    "All pages/html"
);

t.timedLoad(
    "/data/workspaces/help-en/pages/?accept=application/json",
    2000,
    "All pages/json"
);

/* This page is relatively small */
t.test_page_load('Props', 2000);

/* This page is one of the larger ones in help-en */
t.test_page_load('Searching', 2000);

})();
