var t = new Test.Visual();

t.plan(1);

if (!$.browser.safari) {
    t.skipAll("This test is Safari-specific");
}

t.runAsync([
    t.doCreatePage("NotVeryLongLine"),

    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.is(
            t.$('#contentLeft').css('overflow-y'),
            'hidden',
            "Safari needs overflow-y set to 'hidden' to hide the scrollbar"
        );

        t.endAsync();
    }
]);
