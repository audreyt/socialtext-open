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
    var self = this;

    fetchData(entries, 0, function() {
        $(self).each(function() {
            $(this).html(Jemplate.process('nav-list.tt2', {
                loc: loc,
                entries: entries
            }));

            if ($.browser.msie && $.browser.version < 7) {
                $(this).parents('.submenu')
                    .mouseover(function() {
                        $(this).addClass('hover');
                    })
                    .mouseout(function() {
                        $(this).removeClass('hover');
                    });
            }

            $('.scrollingNav', this).each(function() {
                // Show a maximum of 8 entries (AKA cross-browser max-height)
                var li_height = $(this).hasClass('has_icons') ? 30 : 20;
                if ($(this).find('li').size() >= 8) {
                    $(this).height(li_height * 8);
                    $(this).css('overflow-y', 'scroll');
                }
            });

            $('li.scrollingNav li:last, li:last', this).addClass('last');
        });
    });
};

$.fn.peopleNavList = function(nodes) {
    $(this).each(function() {
        $(this).navList([
            { title: loc("nav.people-directory"), href: "/?action=people" },
            {
                url: "/data/people/" + Socialtext.userid + "/watchlist",
                icon: function(p) {
                    return '/data/people/' + p.id + '/small_photo'
                },
                href: function(p) { if (p) return '/st/profile/' + p.id },
                title: function(p) { return p.best_full_name },
                emptyMessage:
                    loc("nav.no-followers")
            }
        ]);
    });
};

})(jQuery);
