(function($) {

var t = new Test.Visual();

t.plan(4);

t.runAsync([
    function() {
        for (var id = 6; id <= 8; id++) {
            jQuery.ajax({
                url:'/data/people/devnull1@socialtext.com/watchlist',
                type:'POST',
                contentType: 'application/json',
                processData: false,
                async: false,
                data: '{"person":{"id":"'+id+'"}}',
                complete: function() {
                    t.ok('Followed person with ID ' + id);
                }
            });
        }

        t.open_iframe("/?profile", t.nextStep());
    },
            
    function() { 
        /* Find the "People I'm following" panel */
        var src = t.$('ul#middleList li:first div.widgetContent iframe')
                   .attr('src');
        t.open_iframe(src, t.nextStep(3000));
    },

    function() { 
        t.$('img:first').css('border', '1px solid black');
        t.$('li.oddRow:first').css('border', '1px solid black');

        t.elements_do_not_overlap(
            t.$('img:first'),
            t.$('li.oddRow:first'),
            "Rows should not overlap each other in [People I'm following]."
        );
        t.endAsync();
    }
]);

})(jQuery);
