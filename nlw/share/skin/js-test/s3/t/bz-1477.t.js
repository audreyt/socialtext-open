var t = new Test.Visual();

t.plan(2);

var v = "Very Long Line Very Long Line"
      + "Very Long Line Very Long Line"
      + "Very Long Line ";

t.runAsync([
    t.doCreatePage(
        v + v + v + v + v + "\n\n"
      + ".pre\n"
      + v + v + v + v + "\n"
      + ".pre\n"
    ),

    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        var clWidth = t.$('#contentLeft').width();

        t.$('#st-page-boxes-toggle-link').click();

        t.isnt(
            clWidth,
            t.$('#contentLeft').width(),
            "Hiding contentRight will change contentLeft's width"
        );

        t.$('#st-page-boxes-toggle-link').click();

        t.is(
            clWidth,
            t.$('#contentLeft').width(),
            "Showing contentRight will change contentLeft's width"
        );

        t.endAsync();
    }
]);
