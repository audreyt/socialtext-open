// Watchlist
if (typeof ST == 'undefined') {
    ST = {};
}

ST.Watchlist = function() {};

ST.Watchlist.prototype = {
    isBeingWatched: false,
    image: null,

    button_activate: function () {
        if (!this.isBeingWatched) {
            var text = document.getElementById('st-watchlist-text');
            if (text) {
                text.className = 'on';
            }
            this.image.src = this._image_src('hover');
        }
        return false;
    },

    button_default: function () {
        var text = document.getElementById('st-watchlist-text');
        if (this.isBeingWatched) {
            if (text) {
                text.innerHTML = loc("Watching this page");
                text.className = 'on';
            }
            this.image.src = this._image_src('on');
        }
        else {
            if (text) {
                text.innerHTML = loc("Watch this page");
                text.className = 'off';
            }
            this.image.src = this._image_src('off');
        }
        return false;
    },

    _image_src: function(type) {
        var star = '';
        if (Socialtext.loc_lang != 'en') {
            star = 'star-';
        }
        return nlw_make_s2_path(
            '/images/st/pagetools/watch-' + star + type + '.gif'
        );
    },

    _toggle_watch_state: function () {
        var wiki_id = Socialtext.wiki_id || Page.wiki_id;
        var action = (this.isBeingWatched) ? 'remove_from' : 'add_to';
        var page_id = this.page_id || Socialtext.page_id;
        var uri = '/' + wiki_id + '/index.cgi' +
                  '?action=' + action + '_watchlist;page=' + page_id +
                  ';_=' + (new Date()).getTime();

        var self = this;
        jQuery.ajax({
            url: uri,
            type: 'get',
            success: function(text) {
                if (text == '1' || text == '0') {
                    self.isBeingWatched = ! self.isBeingWatched;
                    self.button_default();
                } else {
                    self._display_toggle_error();
                }
            },
            error: function() {
                self._display_toggle_error();
            }
        });
    },

    _display_toggle_error: function () {
        if (this.isBeingWatched) {
            alert(loc('Could not remove page from watchlist'));
        }
        else {
            alert(loc('Could not add page to watchlist'));
        }
    },

    _applyArgument: function (arg) {
        if (typeof this[arg.key] != 'undefined') {
            this[arg.key] = arg.value;
        }
    },

    _loadInterface: function (indicator) {
        this.image = indicator;
        if (this.image) {
            if (Socialtext.loc_lang != 'en') {
                if (this.image.src.match(/watch-star-on/)) {
                    this.isBeingWatched = true;
                }
                else {
                    this.isBeingWatched = false;
                }
            }
            else {
                if (this.image.src.match(/watch-on/)) {
                    this.isBeingWatched = true;
                }
                else {
                    this.isBeingWatched = false;
                }
            }

            var self = this;
            jQuery(this.image.parentNode).bind("click", function(e) {
                self._toggle_watch_state(e);
            })
            .hover(
                function() {
                    self.button_activate();
                },
                function() {
                    self.button_default();
                }
            );

            this.button_default();
        }
    }
};
