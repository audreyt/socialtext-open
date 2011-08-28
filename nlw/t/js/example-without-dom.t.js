module("example (Without DOM)");

test("basic sanity test example", function() {
    ok(true, "world is sane.");
    equals(1,1,"math is sane");
    same({a:1},{a:1}, "comparison is sane");
});
