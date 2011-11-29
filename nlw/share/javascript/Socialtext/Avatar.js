(function($){

Avatar = function (node) {
    var self = this;
    this.node = node;
    this.bubble = new Bubble({
        node: node,
        onFirstShow: function() {
            var user_id = $(node).attr('userid');
            self.getUserInfo(user_id);
        }
    });
};

// Class method for creating all avatar popups
Avatar.createAll = function() {
    $('.person.authorized')
        .each(function() { new Avatar(this) });
};

Avatar.prototype = {
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
        this.bubble.showContent( loc('error.user-data') );
    },

    showUserInfo: function(html) {
        var self = this;
        self.bubble.html(html);
        self.person = new Person({
            id: self.id,
            best_full_name: $(self.node).find('.fn').text(),
            email: $(self.node).find('.email').text(),
            restricted: $(self.node).find('.vcard').hasClass('restricted')
        });
        self.person.loadWatchlist(function() {
            self.showCommunicatorInfo();
            self.showSametimeInfo();
            if (!self.person.isSelf() && !self.person.restricted) {
                var link_text = self.person.linkText();
                self.followLink = $('<a href="#">' + link_text + '</a>');
                self.followLink
                    .addClass('followPersonButton')
                    .unbind('click')
                    .click(function(){ 
                        self.person.isFollowing() ? self.stopFollowing() : self.follow();
                        return false;
                    });

                self.bubble.append(
                    $('<div></div>')
                        .addClass('follow')
                        .append(
                            $('<ul></ul>')
                                .append($('<li></li>').append(self.followLink))
                        )
                );
            }
            self.bubble.mouseOver();
        });
    },

    follow: function() {
        var self = this;
        $.ajax({
            url:'/data/people/' + Socialtext.userid + '/watchlist', 
            type:'POST',
            contentType: 'application/json',
            processData: false,
            data: '{"person":{"id":"' + this.person.id + '"}}',
            success: function() {
                self.person.watchlist[self.person.id] = true;
                self.updateFollowLink();
            }
        });
    },

    stopFollowing: function() {
        var self = this;
        $.ajax({
            url:'/data/people/' + Socialtext.userid + '/watchlist/' + this.person.id,
            type:'DELETE',
            contentType: 'application/json',
            success: function() {
                delete self.person.watchlist[self.person.id];
                self.updateFollowLink();
            }
        });
    },

    updateFollowLink: function() {
        var linkText = this.person.linkText();
        if (this.person.isFollowing()) {
            this.followLink.addClass('following');
        }
        else {
            this.followLink.removeClass('following');
        }
        this.followLink.text(linkText);
    },

    showCommunicatorInfo: function() {
        if (window.ocs_helper === undefined)
            return;

        var communicator_elem = $(this.node).find('.communicator');
        var communicator_elem_parent = communicator_elem.parent();
        var communicator_sn = communicator_elem.text();

        ocs_helper.create_ocs_field(communicator_elem, communicator_sn);
    },

    showSametimeInfo: function() {
        // Dynamic sametime script hack

        var sametime_elem = $(this.node).find('.sametime');
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
    }
};

$(function(){
    if (Socialtext.mobile) { return; }
    Avatar.createAll();
});

})(jQuery);
