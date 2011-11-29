(function($){

Person = function (user) {
    $.extend(true, this, user);
}

Person.prototype = {
    loadWatchlist: function(callback) {
        var self = this;

        var params = {};
        params[gadgets.io.RequestParameters.CONTENT_TYPE] =
            gadgets.io.ContentType.JSON;
        var url = location.protocol + '//' + location.host
                + '/data/people/' + Socialtext.userid + '/watchlist';
        gadgets.io.makeRequest(url, function(response) {
            self.watchlist = {};
            $.each(response.data, function(_, user) {
                self.watchlist[user.id] = true;
            });
            callback();
        }, params);
    },

    isSelf: function() {
        return this.self || (Socialtext.real_user_id == this.id);
    },

    isFollowing: function() {
        return this.watchlist[this.id] ? true : false;
    },

    updateFollowLink: function() {
        var linkText = this.linkText();
        this.node.button('option', 'label', linkText).attr('title', linkText);
        if (this.isFollowing()) {
            this.node.addClass('following');
        }
        else {
            this.node.removeClass('following');
        }
    },

    linkText: function() {
        return this.isFollowing() ? loc('do.unfollow')
                                  : loc('do.follow');
    },

    createFollowLink: function($indicator) {
        var self = this;
        if (!this.isSelf() && !this.restricted) {
            var link_text = this.linkText();
            this.node = $indicator
                .addClass('followPersonButton')
                .unbind('click')
                .click(function(){ 
                    self.isFollowing() ? self.stopFollowing() : self.follow();
                    return false;
                });
            this.updateFollowLink();
        }
    },

    follow: function() {
        var self = this;
        $.ajax({
            url:'/data/people/' + Socialtext.userid + '/watchlist', 
            type:'POST',
            contentType: 'application/json',
            processData: false,
            data: '{"person":{"id":"' + this.id + '"}}',
            success: function() {
                self.watchlist[self.id] = true;
                self.updateFollowLink();
                $("#global-people-directory").peopleNavList();
                if ($.isFunction(self.onFollow)) {
                    self.onFollow();
                }
            }
        });
    },

    stopFollowing: function() {
        var self = this;
        $.ajax({
            url:'/data/people/' + Socialtext.userid + '/watchlist/' + this.id,
            type:'DELETE',
            contentType: 'application/json',
            success: function() {
                delete self.watchlist[self.id];
                self.updateFollowLink();
                $("#global-people-directory").peopleNavList();
                if ($.isFunction(self.onStopFollowing)) {
                    self.onStopFollowing();
                }
            }
        });
    }
}

})(jQuery);
