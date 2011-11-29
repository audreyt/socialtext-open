var t = new Test.Visual();

t.plan(3);

t.runAsync([
    t.doCreatePage(
        "VeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLineVeryLongLine"
    ),

    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.is(
            t.$('#contentLeft').css('overflow'),
            'visible',
            "Long content lines overflows rightward as needed" 
        );

        t.ok(
            (t.$('#mainWrap').width() > t.$('#contentLeft').width()),
            "Main wrapper gets resized along with overlong content"
        );

        t.is(
            t.$('#contentLeft').offset().top,
            t.$('#contentRight').offset().top,
            "Long content lines does not cause contentRight to move downward"
        );

        t.endAsync();
    }
]);
