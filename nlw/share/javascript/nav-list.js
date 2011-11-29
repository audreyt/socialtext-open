(function($) {

var LOAD_DELAY = 1500;

function fetchData(entries, index, callback) {
    if (index < entries.length) {
        var entry = entries[index];
        if (entry.url) {
            setTimeout(function() {
                var params = {};
                params[gadgets.io.RequestParameters.CONTENT_TYPE] =
                    gadgets.io.ContentType.JSON;
                var url = location.protocol + '//' + location.host
                        + entry.url;
                gadgets.io.makeRequest(url, function(response) {
                    if (entry.sort)
                        response.data = response.data.sort(entry.sort);
                    entry.data = response.data;

                    fetchData(entries, index + 1, callback);
                }, params);
            }, LOAD_DELAY);
        }
        else {
            // skip loading data, move on to the next entry
            fetchData(entries, index + 1, callback);
        }
    }
    else {
        callback(); // Done loading all data
    }
}

$.fn.navList = function(entries) {
    var $nodes = $(this);

    if (Number(st.viewer.is_guest)) return;

    fetchData(entries, 0, function() {
        $nodes.each(function(_, node) {
            var $node = $(node);
            $node.find('ul').remove();
            
            var $navList = $(Jemplate.process('nav-list.tt2', {
                loc: loc,
                entries: entries
            }));

            $navList
                .appendTo('#globalNav')
                .find('li:last').addClass('last');

            var hovering = false;
            $node.add($navList)
                .mouseover(function() {
                    hovering = true;
                    $navList
                        .show()
                        .position({
                            of: $node,
                            my: 'left top',
                            at: 'left bottom',
                            offset: '0 -4px'
                        });
                })
                .mouseout(function() {
                    hovering = false;
                    setTimeout(function() {
                        if (hovering) return;
                        $navList.hide();
                    }, 50);
                })
        });
    });
};

})(jQuery);
