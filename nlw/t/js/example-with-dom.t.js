module("example (With DOM)");

TestDepLoader.loaddom("example-with-dom.html");

test("basic dom test example", function() {
    ok(true, "world is sane.");
    equals($("#test").html(), "Test", "Dom Is Sane");
});
