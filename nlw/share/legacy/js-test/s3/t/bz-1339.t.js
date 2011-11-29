(function($) {

var t = new Test.Visual();

t.plan(3);

t.runAsync([
    function() {
        t.open_iframe( "/admin/index.cgi?admin_wiki", t.nextStep() );
    },
            
    function() { 
        t.elements_do_not_overlap(
            t.$('#st-search-term'),
            t.$('#mainNav'),
            'Search box should not overlap with the main navigation div'
        );

        t.elements_do_not_overlap(
            t.$('#st-search-term'),
            t.$('#workspaceNav'),
            'Search box should not overlap with the workspace navigation div'
        );

        t.elements_do_not_overlap(
            t.$('#st-search-term'),
            t.$('#st-display-mode-container'),
            'Search box should not overlap with the page display div'
        );

        t.endAsync();
    }
]);

})(jQuery);
