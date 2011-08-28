(function($) {

var t = new Test.Visual();

window.t = t;
if ($.browser.mozilla && $.browser.version.match(/^1\.([0-8]\.|9\.0)/))
    t.skipAll("Gecko 1.9.0.x hijacks RSS target into _top; skipping this test.");

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/?profile", t.nextStep(5000));
    },
            
    function() { 
        var $rss_link = t.$('a.rss-feed');

        t.is(
            $rss_link.attr('target'),
            '_blank',
            "[RSS Feed] link opens in a new window, not the same window"
        );

        t.endAsync();
    }
]);

})(jQuery);
