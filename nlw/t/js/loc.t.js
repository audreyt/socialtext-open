module('l10n');
TestDepLoader.loaddom("empty.html");
TestDepLoader.loadskinjs('s3', 'loc.js');

Socialtext = {};

test('quant', function() {
    equals(loc("[quant,_1,frog]", 1), "1 frog", "1 frog");
    equals(loc("[quant,_1,frog]", 2), "2 frogs", "2 frogs");
    equals(loc("[quant,_1,frog]", 3), "3 frogs", "3 frogs");

    equals(loc("[quant,_1,goose,geese]", 1), "1 goose", "1 goose");
    equals(loc("[quant,_1,goose,geese]", 2), "2 geese", "2 geese");
    equals(loc("[quant,_1,goose,geese]", 3), "3 geese", "3 geese");

    equals(loc("[quant,_1,person,people,nobody]", 0), "nobody", "nobody");
    equals(loc("[quant,_1,person,people,nobody]", 1), "1 person", "1 person");
    equals(loc("[quant,_1,person,people,nobody]", 2), "2 people", "2 people");

    equals(loc("[*,_1,frog]", 1), "1 frog", "1 frog");
    equals(loc("[*,_1,frog]", 2), "2 frogs", "2 frogs");
    equals(loc("[*,_1,frog]", 3), "3 frogs", "3 frogs");

    equals(loc("[*,_1,goose,geese]", 1), "1 goose", "1 goose");
    equals(loc("[*,_1,goose,geese]", 2), "2 geese", "2 geese");
    equals(loc("[*,_1,goose,geese]", 3), "3 geese", "3 geese");

    equals(loc("[*,_1,person,people,nobody]", 0), "nobody", "nobody");
    equals(loc("[*,_1,person,people,nobody]", 1), "1 person", "1 person");
    equals(loc("[*,_1,person,people,nobody]", 2), "2 people", "2 people");
});

test('en locale', function() {
    Socialtext.loc_lang = 'en';
    TestDepLoader.loadskinjs('s3', 'l10n/en.js');

    equals(loc("Oh hi!"), "Oh hi!", "string not in the po file");
    equals(loc("activities.add-tag"), "Add a tag", "string in the po file");
    equals(loc("ago.days=count", 987), "987 days ago", "[_1] expansion");
    equals(
        loc("control.showing=from,to,total", 'a', 'b', 'c'),
        "Showing a - b of c",
        "[_1], [_2] and [_3] expansion"
    );
    equals(
        loc("This %1 and %2 and %3", 'a', 'b', 'c'),
        "This a and b and c",
        "%1, %2 and %3 expansion"
    );
    equals(loc("quotes\"[_1]\\\"\"", '"'), 'quotes"\"""', 'quotes');
});

test('xx locale', function() {
    Socialtext.loc_lang = "xx";
    equals(loc("hello"), "xxxxx", "[_1] xxxxxxxxx");
    equals(
        loc("[_1] are [_2] cool!", "js tests", "so"),
        "js tests xxx so xxxx!",
        "[_1] xxx [_2] xxxxxxxxx"
    );

    // XXX: quant is broken in the xx locale
    //equals(loc("[quant,_1,goose,geese]", 1), "1 goose", "1 goose");
    //equals(loc("[quant,_1,goose,geese]", 2), "2 geese", "2 geese");
});

test("xq locale", function() {
    Socialtext.loc_lang = "xq";
    equals(loc("hello"), "«hello»", "[_1] expansion");
    equals(
        loc("[_1] are [_2] cool!", "js tests", "so"),
        "«js tests are so cool!»",
        "«[_1] and [_2] expansion»"
    );
    equals(loc("[quant,_1,goose,geese]", 1), "«1 goose»", "«1 goose»");
    equals(loc("[quant,_1,goose,geese]", 2), "«2 geese»", "«2 geese»");
});

test("xr locale", function() {
    Socialtext.loc_lang = "xr";
    equals(loc("leet!"), "l337!", "[_1] 3xp4nsi0n");
    equals(
        loc("[_1] are [_2] cool!", "js tests", "so"),
        "js tests 4r3 so c00l!",
        "[_1] 4nd [_2] 3xp4nsi0n"
    );

    // XXX: HREFs are broken by the xr locale
    //equals(
    //    loc('<a href="http://www.google.com">google</a>'),
    //    '<a href="http://www.google.com">g00gl3</a>',
    //    "anchors with the xr locale"
    //);

    equals(loc("[quant,_1,goose,geese]", 1), "1 g00s3", "1 g00s3");
    equals(loc("[quant,_1,goose,geese]", 2), "2 g33s3", "2 g33s3");
});
