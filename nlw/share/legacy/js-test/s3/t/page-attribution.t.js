(function($) {

var t = new Test.Visual();

t.plan(3);

t.runAsync([
    function() {
        t.open_iframe("/admin/index.cgi?admin_wiki", t.nextStep());
    },

    function() {
        // Scroll all the way to the bottom.
        t.scrollTo(20000);

        t.like(
            t.$("#pageAttribution").text(),
            /Created by/,
            "There is page creator info at the bottom of the page"
        );
        t.like(
            t.$("#pageAttribution").text(),
            /Updated by/,
            "There is page updator info at the bottom of the page"
        );
        t.like(
            t.$("#pageAttribution a.revision").text(),
            /\d+ revisions?/,
            "There is a page revision info inside of a pair of parens at the bottom of the page."
        );

        t.endAsync();
    }
]);

})(jQuery);
