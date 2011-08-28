var t = new Test.Visual();

t.plan(2);

t.runAsync([
    t.doCreatePage(
        "{toc:}\n\n"
      + '^^ "Foo"<http://foo.com>\n\n'
    ),

    function() { 
        t.is(
            t.$('div.wafl_box a').length,
            1,
            "The {toc:} is rendered as a box"
        );

        t.is(
            t.$('div.wafl_box a').text(),
            "Foo",
            "The {toc:} link has its title set correctly"
        );

        t.endAsync();
    }
]);
