(function($) {

LikeIndicator = function(opts) {
    this.update(opts);
};

LikeIndicator.prototype = {
    loc: loc,
    limit: 10,
    col_limit: 5,

    _defaults: {
        display: 'button'
    },

    update: function(opts) {
        $.extend(this, this._defaults, opts);
        this.others = this.isLikedByMe ? this.count - 1 : this.count;
        this.onlyFollows = true;
        if (this.node) {
            this.node.find('.like-indicator')
                .removeClass('me')
                .removeClass('others')
                .addClass(this.className());
        }
    },

    render: function ($node) {
        var self = this;

        if ($node) {
            self.node = $node;
            self.node.html(Jemplate.process('like-indicator.tt2', self));
        }
        else {
            self.node.find('.like-indicator')
                .addClass(self.className())
                .removeClass('loading')
                .attr('title', self.text(true))
                .html(self.text(true));
        }

        var $indicator = self.node.find('a.like-indicator');

        // If we already have a bubble, hide it quick before we recreate it
        self.startIndex = 0; // reset startIndex in case it's set

        if (self.bubble) {
            self.renderBubble();
        }
        else {
            var vars = {
                node: $indicator.get(0),
                onFirstShow: function() {
                    self.renderBubble(function() {
                        self.bubble.show();
                    })
                }
            };
            if ($indicator.parents('#controlsRight').size()) {
                vars.topOffset = 10; // XXX: weird
            }
            self.bubble = new Bubble(vars);
        }

        if (!self.bubble.isTouchDevice()) {
            $indicator
                .unbind('click')
                .click(function() { self.toggleLike(); return false });
        }
    },

    renderBubble: function(cb) {
        var self = this;

        var url = self.url + '?' + $.param({
            startIndex: self.startIndex,
            limit: self.limit,
            only_follows: self.onlyFollows ? 1 : 0
        }).replace('&',';'); // Something doesn't like &'s here

        $.getJSON(url, function(likers) {
            self.likers = likers;

            // Split into columns
            self.columns = [];
            $.each(likers.entry, function(i,liker) {
                var col = Math.floor(i/self.col_limit);
                if (!self.columns[col]) self.columns[col] = [];
                self.columns[col].push(liker);
            });

            self.pages = [];
            for (var i=0; i * self.limit < likers.totalResults; i++) {
                self.pages.push({
                    num: i+1,
                    current: i * self.limit == self.startIndex
                });
            }
            var i = 0;

            // Actions:
            var $node = self.bubble.contentNode;
            if (!$node) {
                self.bubble.createPopup();
                $node = self.bubble.contentNode;
            }

            self.bubble.html(Jemplate.process('like-bubble', self));

            $node.find('.like-indicator').click(function() {
                self.toggleLike();
                return false;
            });

            $node.find('.like-filter a').click(function() {
                if (!$(this).parent().hasClass(this.className)) {
                    self.onlyFollows = !self.onlyFollows;
                    self.renderBubble();
                }
                return false;
            });

            $.each(self.pages, function(count, page) {
                $node.find('.page' + page.num).click(function() {
                    self.startIndex = count * self.limit;
                    self.renderBubble();
                    return false;
                });
            });

            if ($.isFunction(cb)) cb();
        });
    },

    toggleLike: function() {
        var self = this;

        self.node.find('.like-indicator')
            .addClass('loading')
            .removeClass('me')
            .removeClass('others');

        var url = self.url + '/' + Socialtext.userid;

        $.ajax({
            url: self.url + '/' + Socialtext.userid,
            type: self.isLikedByMe ? 'DELETE' : 'PUT',
            data: "{}",
            success: function() {
                if (window.signalsBuffer) {
                    // Socialtext Desktop has a long-poll push-client and
                    // so does not need immediate update, otherwise we
                    // run into a race condition.
                    return;
                }

                if (self.isLikedByMe) {
                    self.isLikedByMe = false;
                    self.count--;
                }
                else {
                    self.isLikedByMe = true;
                    self.count++;
                }
                self.render();
            }
        });
    },

    className: function() {
        var classes = [];
        if (this.isLikedByMe) classes.push('me');
        if (this.others) classes.push('others');
        if (!this.mutable) classes.push('immutable');
        if (this.display.match(/^light-/)) classes.push('light');
        return classes.join(' ');
    },

    buttonText: function() {
        return loc(this.isLikedByMe ? 'do.unlike' : 'do.like');
    },

    text: function(with_count) {
        switch(this.display) {
            case 'light-count':
            case 'count':
                return '(' + this.count + ')';
            case 'light-button':
            case 'button':
                return loc(
                    this.isLikedByMe ? 'do.unlike=count' : 'do.like=count',
                    this.count
                );
            case 'light-text_count':
            case 'text_count':
                return loc('like.like=count', this.count);
        }
    },

    likeText: function() {
        var others = this.isLikedByMe
            ? this.likers.totalResults - 1
            : this.likers.totalResults;

        // Possibilities:
        //  like.liked-this.(page|revision).(only-you|(you|not-you)=(followed|others))
        var you_suffix = (
            this.isLikedByMe
                ? ( (others == 0) ? 'only-you' : 'you' )
                : 'not-you'
        );
        var loc_string = [
            'like.liked-this',
            this.type,
            you_suffix
        ].join('.');

        if (you_suffix != 'only-you') {
            loc_string += this.onlyFollows ? '=followed' : '=others'; 
        }

        return loc(loc_string, others);
    },

    likersPercentage: function() {
        return Math.floor(100 * this.count / this.total);
    }
};

$.fn.likeIndicator = function(opts) {
    if (!opts.url) throw new Error('url required');
    if (!opts.type) throw new Error('type required');
    opts.base_uri = opts.base_uri || '';
    $.each(this, function(_, node) {
        if (node._indicator) {
            node._indicator.update(opts);
            node._indicator.render();
        }
        else {
            node._indicator = new LikeIndicator(opts);
            node._indicator.render($(node));
        }
    });
};

})(jQuery);
