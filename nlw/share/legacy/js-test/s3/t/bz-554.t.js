var t = new Test.Visual();

t.plan(4);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

t.runAsync([
    t.doCreatePage('"<&>"<http://example.org/>\n'),

    function() { 
        t.is(
            t.$('div.wiki a').text(),
            "<&>",
            "Special chars in link text is recognized correctly (text)"
        );

        t.is(
            t.$('div.wiki a').attr('href'),
            "http://example.org/",
            "Special chars in link text is recognized correctly (href)"
        );

        t.callNextStep();
    },

    t.doCreatePage('\n'),
    t.doRichtextEdit(),

    function() { 
        t.$('#wikiwyg_button_link').click();
        t.callNextStep(3000);
    },

    function() { 
        t.$('#add-web-link').click();
        t.$('#web-link-text').val('<&>');
        t.$('#web-link-destination').val('http://example.org/');
        t.$('#add-a-link-form').submit();
        t.callNextStep(3000);
    },

    t.doSavePage(),

    function() { 
        t.is(
            t.$('div.wiki a').text(),
            "<&>",
            "Special chars in link text is recognized correctly (text)"
        );

        t.is(
            t.$('div.wiki a').attr('href'),
            "http://example.org/",
            "Special chars in link text is recognized correctly (href)"
        );

        t.endAsync();
    }
]);
