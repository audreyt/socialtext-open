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
        return this.self || (Socialtext.email_address == this.email);
    },

    isFollowing: function() {
        return this.watchlist[this.id] ? true : false;
    },

    updateFollowLink: function() {
        var linkText = this.linkText();
        this.node.text(linkText).attr('title', linkText);
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

    createFollowLink: function() {
        var self = this;
        if (!this.isSelf() && !this.restricted) {
            var link_text = this.linkText();
            this.node = $('<a href="#"></a>')
                .addClass('followPersonButton')
                .click(function(){ 
                    self.isFollowing() ? self.stopFollowing() : self.follow();
                    return false;
                });
            this.updateFollowLink();
            return this.node;
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

Avatar = function (node) {
    var self = this;
    this.node = node;
    $(node)
        .unbind('mouseover')
        .unbind('mouseout')
        .mouseover(function(){ self.mouseOver() })
        .mouseout(function(){ self.mouseOut() });
};

// Class method for creating all avatar popups
Avatar.createAll = function() {
    $('.person.authorized')
        .each(function() { new Avatar(this) });
};

Avatar.prototype = {
    HOVER_TIMEOUT: 500,

    mouseOver: function() {
        this._state = 'showing';
        var self = this;
        setTimeout(function(){
            if (self._state == 'showing') {
                self.displayAvatar();
                self._state = 'shown';
            }
        }, this.HOVER_TIMEOUT);
    },

    mouseOut: function() {
        this._state = 'hiding';
        var self = this;
        setTimeout(function(){
            if (self._state == 'hiding') {
                self.hide();
                self._state = 'hidden';
            }
        }, this.HOVER_TIMEOUT);
    },

    createPopup: function() {
        var self = this;
        this.contentNode = $('<div></div>')
            .addClass('inner');

        this.popup = $('<div></div>')
            .addClass('avatarPopup')
            .mouseover(function() { self.mouseOver() })
            .mouseout(function() { self.mouseOut() })
            .appendTo('body');

        // Add quote bubbles
        this.makeBubble('top', '/images/avatarPopupTop.png')
            .appendTo(this.popup);

        this.popup.append(this.contentNode)
        this.popup.append('<div class="clear"></div>');

        this.makeBubble('bottom', '/images/avatarPopupBottom.png')
            .appendTo(this.popup);
    },

    makeBubble: function(className, src) {
        var absoluteSrc = (''+document.location.href).replace(
            /^(\w+:\/+[^\/]+).*/, '$1' + nlw_make_s3_path(src)
        );
        var $div = $('<div></div>').addClass(className);
	if ($.browser.msie && $.browser.version < 7) {
            var args = "src='" + absoluteSrc + "', sizingMethod='crop'";
            $div.css(
                'filter',
                "progid:DXImageTransform.Microsoft"
                + ".AlphaImageLoader(" + args + ")"
            );
        }
        else {
            $div.css('background', 'transparent url('+absoluteSrc+') no-repeat');
        }
        return $div;
    },

    getUserInfo: function(userid) {
        this.id = userid;
        var self = this;
        $.ajax({
            url: '/data/people/' + userid,
            cache: false,
            dataType: 'html',
            success: function (html) {
                self.showUserInfo(html);
            },
            error: function () {
                self.showError();
            }
        });
    },

    showError: function() {
        this.contentNode
            .html(loc('error.user-data'));
        this.mouseOver();
    },

    showUserInfo: function(html) {
        var self = this;
        self.contentNode.append(html);
        self.person = new Person({
            id: self.id,
            best_full_name: self.popup.find('.fn').text(),
            email: self.popup.find('.email').text(),
            restricted: self.popup.find('.vcard').hasClass('restricted')
        });
        self.person.loadWatchlist(function() {
            var followLink = self.person.createFollowLink();
            if (followLink) {
                $('<div></div>')
                    .addClass('follow')
                    .append(
                        $('<ul></ul>').append($('<li></li>').append(followLink))
                    )
                    .appendTo(self.contentNode);
                }
            self.showCommunicatorInfo();
            self.showSametimeInfo();
            self.mouseOver();
        });
    },

    showCommunicatorInfo: function() {
        var communicator_elem = this.popup.find('.communicator');
        var communicator_elem_parent = communicator_elem.parent();
        var communicator_sn = communicator_elem.text();

        ocs_helper.create_ocs_field(communicator_elem, communicator_sn);
    },

    showSametimeInfo: function() {
        // Dynamic sametime script hack

        var sametime_elem = this.popup.find('.sametime');
        var sametime_elem_parent = sametime_elem.parent();
        var sametime_sn = sametime_elem.text();
        if (sametime_sn) {
            $.getScript("http://localhost:59449/stwebapi/getStatus.js?_="+(new Date().getTime()),
                function () {
                    // The following is to make ie7 happy
                    if (typeof sametime != 'undefined') {
                        sametime_elem.replaceWith(
                            jQuery('<a></a>').
                                css('cursor', 'pointer').
                                text(sametime_sn).
                                click(function() {
                                    sametime_invoke('chat', sametime_sn);
                                })
                        )
                        sametime_elem = sametime_elem_parent.find('a');
                        var sametime_obj = new sametime.livename(sametime_sn, null);
                        updateStatus = function(contact) {
                            sametime_elem.before(jQuery("<img></img>").
                                attr('src', sametime_helper.getStatusImgUrl(contact.status)).
                                attr('title', contact.statusMessage));
                            sametime_elem.before(" ");
                            sametime_elem.attr('title', contact.statusMessage);         
                        }
                        sametime_obj.runActionWithCallback('getstatus', 'updateStatus');
                    }
                });
        }    
    },

    displayAvatar: function() {
        if (!this.popup) {
            this.createPopup();
            var user_id = $(this.node).attr('userid');
            this.getUserInfo(user_id);
        }
        else {
            this.show();
        }
    },

    show: function() {
        // top was calculated based on $node's top, but if there was an
        // avatar image, we want to position off of the avatar's top
        var $img = $(this.node).find('img');
        var $node = $img.size() ? $img : $(this.node);
        var offset = $node.offset();

        // Check if the avatar is more than half of the way down the page
        var winOffset = $.browser.msie ? document.documentElement.scrollTop 
                                       : window.pageYOffset;
        if ((offset.top - winOffset) > ($(window).height() / 2)) {
            this.popup
                .removeClass('underneath')
                .css('top', offset.top - this.popup.height() - 15);
        }
        else {
            this.popup
                .addClass('underneath')
                .css('top', offset.top + $node.height() + 5);
        }

        this.popup.css('left', offset.left - 43 );

        if ($.browser.msie && this.popup.is(':hidden')) {
            var $vcard = $('.vcard', this.contentNode);
            this.popup.fadeIn('def', function() {
                // min-height: 62px
                if ($.browser.msie && $vcard.height() < 65) {
                    $vcard.height(65);
                }
            });
        }
        else {
            this.popup.fadeIn();
        }
    },

    hide: function() {
        if (this.popup) this.popup.fadeOut();
    }

};

$(function(){
    if (Socialtext.mobile) { return; }
    Avatar.createAll();
});

})(jQuery);
