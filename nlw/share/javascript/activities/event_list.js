(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.EventList = function(opts) {
    this.extend(opts);
    this.requires([
        'appdata', 'signals_enabled', 'viewer_id', 'base_uri', 'owner_id',
        'display_limit', 'static_path', 'share', 'onPost', 'mention_user_id'
    ]);
}

Activities.EventList.prototype = new Activities.Base()

$.extend(Activities.EventList.prototype, {
    toString: function() { return 'Activities.EventList' },

    _defaults: {
        events: [],
        placeholderHash: {},
        placeholders: [],
        ondisplay: [],
        signalMap: [],
        minReplies: 2
    },

    /**
     * Event-adding method
     */
    add: function(events, incomplete) {
        var self = this;

        // Allow add(event) and add([evt1,evt2])
        events = $.makeArray(events);

        // Pre sort the events before we actually add them so everything comes
        // in the correct order
        events.sort(function(a, b) {
            return (a.at > b.at) ? 1 : (a.at < b.at) ? -1 : 0;
        });

        $.each(events, function(i, evt) {
            if (!evt.context) evt = self.signalToEvent(evt);
            if (incomplete) evt.incomplete_replies = true;
            evt.modified = true;
            evt.replies = [];
            evt.last_active_at = evt.at;

            // Keep track of the oldest and newest signal
            if (!self._newest || self._newest < evt.at)
                self._newest = evt.at;
            if (!self._oldest || self._oldest > evt.at)
                self._oldest = evt.at;

            switch(evt.event_class + ':' + evt.action) {
                case 'page:edit_save':
                case 'page:comment':
                    if (evt.signal_id) {
                        evt.event_class = 'signal';
                        evt.action = 'signal';
                    }
                    break;
                case 'signal:like':
                case 'signal:unlike':
                    delete evt.signal_id;
                    break;
            }

            // Only thread signals
            if (evt && evt.signal_id) {
                // Do nothing if we have already pre-fetched this signal...
                if (self.placeholderHash[evt.signal_id]) return;

                if (evt.context.in_reply_to) {
                    var reply = evt;
                    evt = self.removeReplyTo(reply);
                    self.addReply(reply, evt);
                }
            }

            self.events.push(evt);
            self.events.sort(function(a, b) {
                return(
                    (a.last_active_at > b.last_active_at)
                        ? -1
                        : (a.last_active_at < b.last_active_at) ? 1 : 0
                )
            });
        });
    },

    removeReplyTo: function(reply) {
        // Try to find the original signal
        var reply_to_id = reply.context.in_reply_to.signal_id;
        var reply_to;

        var reply_to_idx = this.findSignalIndex(reply_to_id);

        // Try to find the original signal
        var reply_to;
        if (reply_to_idx == -1) {
            reply_to = this.placeholderSignal(reply_to_id);
        }
        else {
            reply_to = this.events[reply_to_idx];

            // Remove the original unless its a placeholder
            this.events.splice(reply_to_idx, 1);
        }

        return reply_to;
    },

    addReply: function(reply, reply_to) {
        // Keep a count of replies that will either be accurate,
        // or overridden when we fetch /data/signal/:signal_id
        if (!reply_to.num_replies) reply_to.num_replies = 0;

        // Add the reply only if it's not already in reply_to.replies.
        // (Duplication could happen if the same reply is first fetched
        //  via "click to expand", and then again via "More").
        if ($.grep(reply_to.replies, function(e) {
            return e.signal_id == reply.signal_id;
        }).length == 0) {
            reply_to.replies.push(reply);
        }

        reply_to.replies.sort(function(a, b) {
            return a.at > b.at ? 1 : a.at < b.at ? -1 : 0
        });

        if (reply.at > reply_to.last_active_at) {
            /* This is a new reply:
             * Increment num_replies and update `last_active_at`
             */
            reply_to.num_replies++;
            reply_to.last_active_at
                = reply_to.replies[ reply_to.replies.length -1 ].at;
        }

        // Don't set modified to true on both the parent and its
        // child
        reply_to.modified = true;
        if (reply_to.modified) reply.modified = false;

        // If this reply is part of a list of incomplete replies, set that
        // parameter on the parent signal
        if (reply.incomplete_replies) reply_to.incomplete_replies = true
    },

    contains: function(id) {
        return $.grep(this.events, function(e) {
            return e.signal_id == id;
        }).length ? true : false;
    },

    size: function() { return this.events.length },

    oldest: function() { return this._oldest },
    newest: function() { return this._newest },

    /**
     * clear
     */
    clear: function() {
        // Remove all visible events
        $.each(this.events, function(i, evt) {
            if (evt.$node) evt.$node.remove();
        });
        this.events = [];
        this._newest = undefined;
        this._oldest = undefined;
    },

    addOnDisplayHandler: function(cb) {
        this.eventList.addOndisplayHandler(cb);
    },

    updateDisplay: function() {
        var self = this;
        if (self._paused);

        // Run all ondisplay callbacks
        while (self.ondisplay.length) self.ondisplay.shift()();

        var events = self.filteredEvents(this.events);
        $.each(events, function(i, evt) {
            if (!evt) return;

            // Remove old events
            if (i >= self.display_limit) {
                if (evt.$node) {
                    evt.$node.remove();
                    evt.$node = undefined
                }
                return;
            }

            if (!evt.$node) {
                if (evt.signal_id && self.appdata.isShowingSignals()) {
                    var $node = self.findSignalNode(evt.signal_id);
                    if ($node.size()) {
                        // A node already exists; re-use it instead of
                        // introducing dup nodes for this signal. {bz: 4493}
                        evt.$node = $node;
                    }
                }
                // If we couldn't find the node, create it here
                if (!evt.$node) evt.$node = $('<div class="event"></div>');

                evt.modified = true;
                if (i == 0) {
                    evt.$node.prependTo(self.node);
                }
                else {
                    evt.$node.insertAfter(events[i-1].$node);
                }
                if (evt.signal_id && self.appdata.isShowingSignals()) {
                     evt.$node.addClass('signal');
                }
            }

            // Change all replies to link to the parent signal
            $.each(evt.replies, function(i, reply) {
                reply.context.uri
                    = evt.context.uri + "?r=" + reply.context.hash;
            });

            var update = false;
            if (evt.modified) {
                self.renderEvent(evt);
            }
            else if (evt.replies && evt.replies.length) {
                $.each(evt.replies, function(j, reply) { 
                    if (!reply) return;

                    // Remove old replies
                    if (j < evt.replies.length - evt.max_replies) {
                        if (reply.$node) {
                            update = true;
                            reply.$node.remove();
                            reply.$node = undefined
                        }
                    }
                    else {
                        // Render event
                        if (!reply.$node || !reply.$node.size()) {
                            var $reply = self.findSignalNode(reply.signal_id);
                            if ($reply.size()) {
                                // A node already exists; re-use it instead of
                                // introducing dup nodes for this signal.
                                // {bz: 4493}
                                reply.$node = $reply;
                            }
                            else {
                                reply.$node = $('<div class="reply"></div>');
                            }

                            reply.modified = true;
                            var first = evt.replies.length
                                      - evt.max_replies;
                            if (j == 0 || j == first) {
                                reply.$node.insertAfter(
                                    evt.$node.find('.older')
                                );
                            }
                            else {
                                reply.$node.insertAfter(
                                    evt.replies[j-1].$node
                                );
                            }
                        }
                        if (reply.modified) {
                            self.renderEvent(reply);
                            update = true;
                        }
                    }
                });

                if (update) {
                    evt.$node.find('.older').html(
                        self.processTemplate('older_replies', {
                            'event': evt
                        })
                    );
                    if (evt.$node.find('.older div').size()) {
                        evt.$node.find('.outerEventText')
                            .removeClass('lighttick');
                    }
                    else {
                        evt.$node.find('.outerEventText')
                            .addClass('lighttick');
                    }
                }
            }

            // Move the node to it's proper location if it isn't
            // already there.
            if (i == 0) {
                if (evt.$node.prev().size()) {
                    evt.$node.prependTo(self.node);
                }
            }
            else if (!evt.$node.prev().eq(events[i-1].$node)) {
                evt.$node.insertAfter(events[i-1].$node);
            }
        });

        self.node.find('.event.odd').removeClass('odd');
        self.node.find('.event:odd').addClass('odd');

        if (self.reply_id) {
            self.findSignalNode(self.reply_id).addClass('selected');
        }

        // Now fetch the reply-to signals we've added placeholders for
        self.showPlaceholders();

        if ($.mobile && $.isFunction($.mobile.silentScroll) && !$.mobile.silentScrollInitialized) {
            $.mobile.silentScroll();
            $.mobile.silentScrollInitialized = true;
        }
    },

    renderEvent: function(evt) {
        var self = this;
        var html;

        if (evt.signal_id && !self.appdata.isShowingSignals()) {
            // For {bz: 3822}, if we are not displaying signals, then
            // don't offer the "Reply" row to edit_save event/signals.
            delete evt.signal_id;
            if (evt.context) delete evt.context.uri;
        }

        if (evt.signal_id && self.appdata.isShowingSignals() && !self.signal_id) {
            var network = self.appdata.get('network');
            if (network && network.group_id) {
                var group_ids = evt.context.group_ids;
                if (group_ids && ($.grep(group_ids, function(g) { return (g == network.group_id) }).length == 0)) {
                    delete evt.signal_id;
                    if (evt.context) delete evt.context.uri;
                }
            } 
            else if (network && network.account_id) {
                var account_ids = evt.context.account_ids;
                if (account_ids && ($.grep(account_ids, function(a) { return (a == network.account_id) }).length == 0)) {
                    delete evt.signal_id;
                    if (evt.context) delete evt.context.uri;
                }
            } 
        }

        try {
            if (!evt.$node) throw new Error("No event node!");
            self.decorateEvent(evt);
            for (var i in evt.replies) {
                self.decorateEvent(evt.replies[i]);
            }
            var template = evt.in_reply_to || evt.context.in_reply_to
                         ? 'activities/reply.tt2'
                         : 'activities/event.tt2';
            html = self.processTemplate(template, { 'event': evt });
        }
        catch(e) {
            throw e;
            self.showError(typeof(e) == 'string' ? e : e.message);
            return;
        }

        if (evt.signal_id) {
            var $node = self.findSignalNode(evt.signal_id);
            if ($node.size()) {
                // A node already exists; re-use it instead of
                // introducing dup nodes for this signal. {bz: 4493}
                evt.$node = $node;
            }
            else {
                evt.$node.addClass('signal' + evt.signal_id);
            }
        }
        evt.$node.empty();
        evt.$node.append(html);

        evt.$node.find('.signal_body a').each(function(_, a) {
            $(a).attr('target', '_blank');
        });

        if ($.mobile) {
            $('div.eventText div.signal_body a', evt.$node).each(
                function() {
                    if ($(this).attr('href').
                        indexOf('/?action=search_signals') == 0) {
                        // Remove the <A> around the hashtag - a hack to fix 
                        // {bz: 5046} until signal search is provided in mobile
                        $(this).replaceWith($(this).contents());
                    }
                });
            $('div.eventText div.metadata a', evt.$node).attr({
                rel: 'external'
            }).each(function(){
                $(this).attr(
                    'href',
                    $(this).attr('href')
                           .replace(/^\/st\/profile\b/, '/m/profile')
                           .replace(/^\/st\/signals\b/, '/st/m/signals')
                );
            });
        }

        /* Don't allow the action icons to overlap with metadata when
         * the window is shrunk down. (.outer makes this S3 only)
         */
        evt.$node.find('.outer .metadata').css(
            'padding-right', evt.$node.find('.actions').width() + 'px'
        );

        // self event has been rendered, so we can reset the modified flag
        // as well as the modified flag of all its replies
        evt.modified = false;
        self.attachEventActions(evt);
        self.attachThumbnailActions(evt);

        self.ensureNewestReplies(evt);

        $.each(evt.replies, function(i, reply) {
            reply.$node = self.findSignalNode(reply.signal_id);
            reply.modified = false;
            self.attachEventActions(reply);
            self.attachThumbnailActions(reply);
        });
    },

    showUnreadCount: function() {
        var self = this;
        var new_events = 0
        var new_replies = 0

        for (var i = 0; i < this.display_limit; i++) {
            var evt = this.events[i];
            if (!evt) continue;
            if (!evt.$node) {
                new_events++;
            }
            if (evt.replies) {
                var start = Math.max(evt.replies.length - evt.max_replies,0);
                for (var j = start; j < evt.replies.length; j++){
                    var reply = evt.replies[j];
                    if (reply && !reply.$node) new_replies++;
                }
            }
        }

        if (new_events || new_replies) {
            self._paused = true;
            self.clearMessages('newMessages');
            self.showMessageNotice({
                className: 'newMessages',
                new_count: new_events + new_replies,
                links: {
                    '.update': function() {
                        self.clearMessages('newMessages');
                        self._paused = false;
                        self.updateDisplay();
                        return false;
                    }
                }
            })
        }
    },

    updateTimestamps: function() {
        var self = this;
        self.node.find('.event .ago').each(function(i, span) {
            var ago_text = self.processTemplate('activities/ago.tt2', {
                at: $(span).attr('value')
            });
            if (ago_text != $(span).text()) {
                $(span).text(ago_text);
            }
        });
    },

    filteredEvents: function() {
        var self = this;

        var events = self.events;

        // TODO Filter by type

        // TODO Filter by target network

        // TODO Filter by feed

        /**
         * Prevent private signals from showing up when you look at your own
         * profile page 
         */
        if (self.mention_user_id) {
            events = $.grep(events, function(e) {
                if (!e.person) return true; // not a direct message
                var from_me = e.actor.id == self.viewer_id;
                var from_you = e.actor.id == self.mention_user_id;
                var to_you = e.person.id == self.mention_user_id;
                var to_me = e.person.id == self.viewer_id;
                return (from_me && to_you) || (from_you && to_me);
            })
        }

        var feed = this.appdata.get('feed');
        if (feed && feed.id == 'feed-conversations') {
            $.each(events, function(_,evt) { evt.incomplete_replies = true });
        }
        else if (feed && feed.id == 'feed-user') {
            events = $.grep(events, function(e) {
                // Owner created this event
                if (self.owner_id == e.actor.id) return true;

                // Owner was sent this signal privately
                if (e.person && self.owner_id == e.person.id) return true;

                // Owner is mentioned in a topic in the thrad or reply
                if (e.context) {
                    var mentioned = false;

                    // Check the thread signal for user topics, then we
                    // can just assume the replies have the correct topics
                    $.each(e.context.topics || [], function(j,t) {
                        if (t.user_id == self.owner_id) mentioned = true;
                    });
                    if (mentioned) return true;

                    // Iterate over all replies, however, if one contains
                    // the topic, we will need to mark this thread as
                    // incomplete since we might not have the most recent
                    // reply, and we'll need to fetch replies starting at
                    // the beginning when the thread is expanded
                    $.each(e.replies, function(i, reply) {
                        if (reply.actor.id == self.owner_id) mentioned = 1;
                        $.each(reply.context.topics || [], function(j,t) {
                            if (t.user_id == self.owner_id)
                                mentioned = true;
                        });
                    });
                    if (mentioned) {
                        e.incomplete_replies = true;
                        return true;
                    }
                }
            });
        }
        return events;
    },

    findSignalNode: function(id) {
        return this.node.find('.signal'+id);
    },

    findSignalIndex: function(signal_id) {
        var idx = -1;
        $.each(this.events, function(i,e) {
            if (e && e.signal_id == signal_id) idx = i;
        });
        return idx;
    },

    placeholderSignal: function(signal_id) {
        this.placeholderHash[signal_id] = true;
        this.placeholders.push(signal_id);
        return {
            num_replies: 0,
            modified: true,
            actor: { id: "0" },
            event_class: 'placeholder',
            signal_id: signal_id,
            context: { body: 'placeholder' },
            replies: [],
            last_active_at: ''
        }
    },

    /**
     * This function will return true if any replies have open wikiwygs
     */
    paused: function() {
        return $(this.node).find('.replies .wikiwyg iframe')
            .size() ? true : false;
    },

    signalToEvent: function(signal) {
        return $.extend({
            event_class: 'signal',
            action: 'signal',
            modified: true,
            person: signal.recipient,
            actor: {
                id: signal.user_id,
                best_full_name: signal.best_full_name,
                uri: '/st/profile/' + signal.user_id
            },
            context: {
                annotations: signal.annotations,
                attachments: signal.attachments,
                account_ids: signal.account_ids,
                group_ids: signal.group_ids,
                body: signal.body,
                in_reply_to: signal.in_reply_to,
                hash: signal.hash,
                uri: signal.uri,
                topics: $.map(signal.mentioned_users || [], function(user){
                    return {
                        best_full_name: user.bestfullname,
                        user_id: user.id
                    }
                })
            },
            replies: []
        }, signal);
    },

    findSignal: function(signal_id, func) {
        var self = this;
        $.each(this.events, function(i, evt) {
            if (evt && evt.signal_id) {
                if (evt.signal_id == signal_id) {
                    func([i, evt]);
                }
                else {
                    var found = false;
                    $.each(evt.replies, function(j, reply) {
                        if (reply.signal_id == signal_id) {
                            func([i, evt], [j, reply]);
                            return false;
                        }
                    });
                    if (found) return false;
                }
            }
        });
    },

    likeSignal: function(like) {
        var self = this;
        self.findSignal(like.signal_id, function(evt, reply) {
            evt = reply ? reply[1] : evt[1];
            if (evt && evt.$node) {
                evt.likers.push(like.actor);
                evt.likers = $.unique(evt.likers);
                self.updateLikeIndicator(evt);
            }
        });
    },

    unlikeSignal: function(unlike) {
        var self = this;
        self.findSignal(unlike.signal_id, function(evt, reply) {
            evt = reply ? reply[1] : evt[1];
            if (evt && evt.$node) {
                evt.likers = $.grep(evt.likers, function(id) {
                    return Number(id) != unlike.actor
                });
                self.updateLikeIndicator(evt);
            }
        });
    },

    removeSignalFromDisplay: function(signal) {
        var self = this;

        // Remove the signal from this.events
        this.findSignal(signal.signal_id, function(evt, reply) {
            if (reply) {
                // remove reply
                evt[1].replies.splice(reply[0], 1);
                evt[1].num_replies = evt[1].replies.length;
            }
            else {
                // remove reply
                self.events.splice(evt[0], 1);
                return false;
            }
        });

        var $node = this.node.find('.signal' + signal.signal_id);
        $node.animate({height: 0}, 'slow', 'linear', function() {
            $node.remove();
        });
    },

    showPlaceholders: function() {
        var self = this;
                
        // Fetch all placeholders at once
        var placeholders = self.placeholders;
        if (!placeholders.length) return;
        self.placeholders = []; // reset
        var uri = self.base_uri + '/data/signals/' + placeholders.join(',');

        self.makeRequest(uri, function(data) {
            // Single signals are returned as a hash, not an array
            var signals = data.data instanceof Array ? data.data : [data.data];

            $.each(signals, function(i, signal) {
                // Replace placholder with the actual signal
                signal = self.signalToEvent(signal);
                var idx = self.findSignalIndex(signal.signal_id);
                var pholder = self.events.splice(idx, 1, signal)[0];

                // transfer replies and $node to the signal
                signal.replies = pholder.replies;
                signal.$node = pholder.$node;
                signal.incomplete_replies = pholder.incomplete_replies;
                signal.last_active_at = pholder.last_active_at || signal.at;

                // Change all replies to link to the parent signal
                $.each(signal.replies, function(i, reply) {
                    reply.context.uri
                        = signal.context.uri + "?r=" + reply.context.hash;
                });

                if (signal.$node) {
                    // if we don't get here, this signal is too old to
                    // display
                    self.renderEvent(signal);

                    // Fetch replies *only* if we don't have enough
                    // already
                    if (signal.num_replies > signal.replies.length) {
                        self.showOlderReplies(signal);
                    }
                }
            });
        }, true);
    },

    visibleReplies: function(evt) {
        if (!evt.replies) return [];
        return evt.replies.slice(- this.repliesToShow(evt));
    },

    repliesToShow: function(evt) {
        if (typeof(evt.max_replies) == 'undefined') evt.max_replies = 2;
        return evt.replies.length > evt.max_replies
            ? evt.max_replies : evt.replies.length;
    },

    signalTargets: function(evt) {
        if (!evt.signal_id) return [];

        var targets = [];

        if (!evt.context) evt = this.signalToEvent(evt);

        var account_ids = evt.context.account_ids || [];
        $.each(this.appdata.accounts(), function(i, account) {
            if ($.grep(account_ids, function(a) { return (a == account.account_id) }).length) {
                targets.push(account.account_name);
            }
        });

        var group_ids = evt.context.group_ids || [];
        $.each(this.appdata.groups(), function(i, group) {
            if ($.grep(group_ids, function(g) { return (g == group.group_id) }).length) {
                targets.push(group.name);
            }
        });

        return targets;
    },

    signalClass: function(evt) {
        if (!evt.signal_id) return;

        var self = this;
        var cx = evt.context;

        // Check if the signal is private - This trumps "mention" below ({bz: 4942}).
        if (evt.person) return 'private';

        // Check if you are mentioned
        var is_mentioned = $.grep(cx.topics || [], function(topic) {
            return topic.user_id == self.viewer_id;
        }).length ? true : false;
        if (is_mentioned) return 'mention';

        return;
    },

    setupEditor: function(evt) {
        var self = this;
        var network_name =
            (evt.context.account_ids && evt.context.account_ids.length)
                ? 'account-' + evt.context.account_ids[0]
                : (evt.context.group_ids && evt.context.group_ids.length)
                    ? 'group-' + evt.context.group_ids[0]
                    : self.appdata.getDefaultFilter('signal_network').value;
        self.editor = new Activities.Editor({
            node: evt.$node.find('.wikiwyg'),
            evt: evt,
            share: self.share,
            prefix: self.prefix,
            static_path: self.static_path,
            base_uri: self.base_uri,
            network: self.appdata.getByValue('signal_network', network_name),
            onPost: function(signal) {
                self.onPost(signal);
                self.add(signal);
                self.updateDisplay();
                self.scrollToSignal(signal.signal_id);
            },
            onBlur: function() {
                self.editor.getWikitext(function(wikitext) {
                    /* {bz: 4208}:
                     * Close the reply iff the user only entered whitespaces.
                     */
                    if (!/\S/.test(wikitext)) {
                        self.renderEvent(evt);
                    }
                });
            }
        });
        self.editor.setupWikiwyg();
    },

    showLightbox: function($a) {
        var self = this;
        var url = $a.attr('href');
        var $video = $a.find('img.video');
        socialtext.dialog.show('activities-show-video', {
            title: $video.attr('title') || loc('activities.attachment'),
            params: {
                url: $a.attr('href'),
                video: $video.size(),
                width: $video.data('width') || 400,
                height: $video.data('height') || 300
            }
        });
    },

    attachThumbnailActions: function(evt) {
        var self = this;
        evt.$node.find('.signal_thumbnails a').unbind('click').click(function(){
            // No popup at all for mobile UI
            if ($.mobile) {
                return true;
            }

            if ($(this).find('img.video').length > 0) {
                var deviceAgent = (navigator.userAgent || '').toLowerCase();
                if (/\b(?:iphone|ipod|ipad)\b/.test(deviceAgent)) {
                    // No video popup for iOS
                    return true;
                }
            }

            self.showLightbox($(this));
            return false;
        });

        evt.$node.find('.signal_thumbnails img.video').css('visibility', 'hidden').load(function(){
            var $img = $(this);
            if ($img.hasClass('hasOverlay')) { return }
            var size = Math.min($img.width(), $img.height()) - 10;
            if (size <= 0) {
                setTimeout(function(){
                    $img.triggerHandler('load');
                }, 100);
                return;
            }
            $img.addClass('hasOverlay');
            var $overlay = $('<img />', {
                src: self.base_uri + "/static/images/video-play-overlay.gif",
                width: size,
                height: size,
                title: $img.attr('title')
            }).hover(function(){
                $overlay.css('opacity', 0.75);
            }, function(){
                $overlay.css('opacity', 0.5);
            }).css({
                zIndex: 1,
                opacity: 0.5,
                position: 'relative',
                width: size + 'px',
                height: size + 'px',
                top: Math.max(1, Math.ceil((size - $img.height()) / 2)),
                left: Math.ceil(($img.width() - size) / 2),
                marginRight: (-size) + "px",
                display: 'none'
            });
            $img.css('visibility', 'visible');
            $overlay.insertBefore($img.hover(function(){
                $overlay.css('opacity', 0.75);
            }, function(){
                $overlay.css('opacity', 0.5);
            })).show();
        });

        this.updateLikeIndicator(evt);
    },

    updateLikeIndicator: function(evt) {
        var self = this;
        var selector = evt.context.in_reply_to ? '.like-reply' : '.like-signal';

        if (evt.person
            || (!self.appdata.pluginsEnabled('like'))
            || (typeof(evt.likers) == 'undefined')
        ) {
            evt.$node.find(selector).hide();
            return;
        }

        /* Like/Unlike */
        evt.likers = $.map(evt.likers || [], function(id) {
            return Number(id);
        });
        evt.$node.find(selector).likeIndicator({
            isLikedByMe: $.inArray(Number(self.viewer_id), evt.likers) > -1,
            count: evt.likers.length,
            total: evt.likers.length,
            url: self.base_uri + "/data/signals/" + evt.signal_id + '/likes',
            base_uri: self.base_uri,
            type: "signal",
            display: 'light-count',
            mutable: true
        });
    },

    signalSnippet: function(signal) {
        var $div = $('<div></div>').html(signal.context.body);

        // Decode html
        $div.html($div.text());

        // Truncate and add ellipsis
        return Jemplate.Filter.prototype.filters.label_ellipsis(
            $div.text(), 40
        );
    },

    attachEventActions: function(evt) {
        var self = this;

        evt.$node.find('.wikiwyg').click(function() {
            $(this).addClass('focused');
            self.setupEditor(evt);
        });

        evt.$node.find('.older').click(function() {
            $(this).find('.loading').show();
            $(this).find('.click_to').hide();
            evt.max_replies = $('div:first', this).hasClass('closed')
                ? Infinity : 2;
            if (evt.max_replies > evt.replies.length) {
                self.showOlderReplies(evt);
            }
            else {
                self.updateDisplay();
            }
            return false;
        });

        evt.$node.find('.total').click(function() {
            evt.$node.find('.toggle.closed').click();
        });

        $('.replyLink:first', evt.$node).click(function (e) {
            self.startReply(evt);
            return false;
        });

        // hook up event icon events, if available
        var $actions = evt.$node.find('.actions:first');
        if (!$actions) { return false };

        evt.$node.find('> .indented:not(.replies) .hideLink:first').click(function (e) {
            self.hideEvent(evt);
            return false;
        });
        evt.$node.find('> .indented:not(.replies) .expungeLink:first').click(function (e) {
            self.expungeEvent(evt);
            return false;
        });
    },

    /* XXX: Duplicate code is in bubble.js */
    isTouchDevice: function() {
        try {
            document.createEvent("TouchEvent");
            return true;
        } catch (e) {
            return false;
        }
    },

    startReply: function(evt) {
        evt.open = true;
        this.renderEvent(evt);
        evt.$node.find('.wikiwyg').click();
        this.scrollTo(evt.$node);
    },

    scrollToSignal: function(id) {
        var self = this;
        var $reply = self.findSignalNode(id);

        var convHeight = $reply.parent().parent().height();
        var $elem = (convHeight > $(window).height()) ? $reply : this.node;

        self.scrollTo($elem)
    },

    hideEvent: function(evt) {
        var self = this;
        var confText = loc("activities.confirm-delete=target", evt.replies.length ? loc('activities.entire-conversation') : loc('activities.signal'));
        if (confirm(confText)) {
            var url = self.base_uri + '/data/signals/'+evt.signal_id+'/hidden';
            self.makePutRequest(url, function() {
                self.removeSignalFromDisplay(evt);
            });
        }
    },

    expungeEvent: function(evt) {
        var self = this;
        var confText = loc("activities.confirm-expunge=target", evt.replies.length ? loc('activities.entire-conversation') : loc('activities.signal'));
        if (confirm(confText)) {
            var url = self.base_uri + '/data/signals/'+evt.signal_id;
            self.makeDeleteRequest(url, function() {
                self.removeSignalFromDisplay(evt);
            });
        }
    },

    decorateEvent: function(evt) {
        var pretty = '';

        evt.context = evt.context || {};

        var annos = evt.context.annotations;
        if (!annos) annos = [] 
        var thumbnails = [];
        var evilurl = /\"|\n/;

        for (var index in annos) {
            var anno = annos[index];
            for (var namespace in anno) {
                // there is only ever one namespace in an anno. Weird, eh?
                if (namespace == 'ua') continue;
                if (namespace == 'link') continue;
                if (namespace == 'icon') {
                    var title = anno[namespace]['title'];
                    if (title) {
                        evt.icon_title = title;
                    }
                }
                if (namespace == 'img') {
                    // Do special processing for imgs to make it easy to
                    // display inline
                    var raw_thumb = anno[namespace]['thumbnail'];
                    if (raw_thumb) {
                        var thumb = gadgets.json.parse(raw_thumb);
                        if (thumb['src'] && thumb.src.search(/\"|\n/) == -1) {
                            thumbnails.push({
                                image: thumb.src,
                                url: thumb.href,
                                title: thumb.alt,
                                type: thumb.type
                            });
                        }
                    }
                    continue;
                }
                if (namespace == 'thumbnail') {
                    thumbnails.push(anno[namespace]);
                    continue;
                }
                if (namespace == 'video') {
                    thumbnails.push(anno[namespace]);
                    continue;
                }
                for (var key in anno[namespace]) {
                    pretty += namespace+'|'+key+'|'+anno[namespace][key]
                    pretty += '\n   ';
                }
            };
        }
        if (pretty.length)
            evt.context.annotations_pretty = pretty;
        
        evt.thumbnails = thumbnails;
        
        var attachments = evt.context['attachments'];
        if (!attachments) attachments = [];
        $.each(attachments, function(i,attach) {
            var rawcl = attach.content_length;
            var prettycl = '';
            if (rawcl < 1000) {
                prettycl = loc('file.size=bytes', rawcl);
            } else if (rawcl < 10000) {
                prettycl = loc('file.size=kb', (rawcl/1000).toFixed(2));
            } else if (rawcl < 100000) {
                prettycl = loc('file.size=kb', (rawcl/1000).toFixed(1));
            } else if (rawcl < 1000000) {
                prettycl = loc('file.size=kb', (rawcl/1000).toFixed(0));
            } else if (rawcl < 10000000) {
                prettycl = loc('file.size=mb', (rawcl/1000000).toFixed(2));
            } else if (rawcl < 100000000) {
                prettycl = loc('file.size=mb', (rawcl/1000000).toFixed(1));
            } else {
                prettycl = loc('file.size=mb', (rawcl/1000000).toFixed(0));
            }
            attach.pretty_content_length = prettycl;
        });
    },

    /*
     * TODO comment on chaining many small requests
     */
    replyFetchLimit: 50,
    showOlderReplies: function(evt, force) {
        var self = this;

        // This event has had replies fetched in an order that is not
        // guaranteed to be in the correct order
        var incomplete = evt.max_replies == Infinity
            && evt.incomplete_replies
            && evt.num_replies > evt.replies.length;
        if (incomplete) {
            $.each(evt.replies, function(i, reply) {
                if (reply.$node) {
                    self.ondisplay.push(function() {
                        reply.$node.remove();
                    });
                }
            });
            evt.replies = [];
            evt.incomplete_replies = false;
        }
        
        var limit = this.replyFetchLimit;

        var count = evt.max_replies - evt.replies.length;
        if (count > limit) {
            count = limit;
        }
        if (count <= 0) return;

        var uri = self.base_uri
                + '/data/signals/' + evt.signal_id
                + '/replies?html=0;direct=both'
                + ';count=' + count
                + (evt.replies.length ? ';before='+evt.replies[0].at : '');

        self.makeRequest(uri, function(data) {
            var replies = data.data || [];
            if (replies.length) {
                $.each(replies, function(i, reply) {
                    var reply = self.signalToEvent(reply);
                    evt.replies.unshift(reply);
                });
                setTimeout(function() {
                    self.showOlderReplies(evt, force);
                }, 1);
            }
            else {
                if (evt.max_replies == Infinity) {
                    evt.num_replies = evt.replies.length;
                }

                if (evt.replies.length <= limit) {
                    self.updateDisplay();
                    return;
                }

                /* More than 50 replies - let's render in batches of 50. */
                var all_replies = evt.replies.reverse();
                evt.replies = [];
                var doUpdateDisplay = function() {
                    var cur_replies = all_replies.splice(0, limit);
                    if (!cur_replies || cur_replies.length == 0) { return; }
                    evt.replies = cur_replies.reverse().concat(evt.replies);
                    self.updateDisplay();
                    setTimeout(doUpdateDisplay, 1);
                };
                setTimeout(doUpdateDisplay, 1);
            }
        }, force);
    },

    updateMinReplies: function(new_min) {
        var self = this;
        self.minReplies = new_min;
        $.each(self.events, function(i, evt) {
            self.ensureNewestReplies(evt);
        });
    },

    ensureNewestReplies: function(evt) {
        var self = this;

        // evt.num_replies can be undefined if there are no replies
        var num_replies = typeof(evt.num_replies) == 'undefined'
                        ? 0 : evt.num_replies;

        // Set the minimum to minReplies unless that's more than are available
        var minimum = self.minReplies;
        if (minimum > num_replies) minimum = num_replies;

        // Set the maximum to max_replies,  and if that's more than we have 
        // available, just fetch all the server has
        var maximum = evt.max_replies;
        if (maximum > num_replies) maximum = num_replies;

        // Check if we have enough
        if (evt.replies.length >= minimum || maximum <= 0) return;

        evt.incomplete_replies = false;
        evt.replies = [];

        var uri = self.base_uri
                + '/data/signals/' + evt.signal_id
                + '/replies?html=0;direct=both'
                + ';count=' + maximum; // Fetch as many as possible

        self.makeRequest(uri, function(data) {
            var replies = data.data || [];
            if (replies.length) {
                evt.replies = $.map(replies.reverse(), function(r) {
                    return self.signalToEvent(r);
                });

                // We got less than we requested, update num_replies
                if (evt.replies.length < maximum) {
                    evt.num_replies = evt.replies.length;
                }

                self.renderEvent(evt);

                if (self.reply_id) {
                    self.findSignalNode(self.reply_id).addClass('selected');
                }
            }
        });
    },

    canDeleteSignal: function(evt) {
        var self = this;
        if (this.appdata.isBusinessAdmin()) return true;
        if (evt.actor.id == this.viewer_id) return true;

        // No such thing as account admin, so if the signal targets an
        // account, we can't delete it
        var account_ids = evt.context.account_ids || [];
        if (!account_ids.length) {
            // There's no way to signal to multiple groups and no
            // accounts, so we only check if the signal was sent to a
            // single group that we can admin.
            var group_ids = evt.context.group_ids || [];
            if (group_ids.length == 1) {

                var can_admin = false;
                $.each(this.appdata.groups(), function(i, group) {
                    // Check if this is the right group
                    if (group.group_id == group_ids[0] && group.admins) {
                        // Check if we're an admin
                        $.each(group.admins, function(i, user) {
                            if (user.user_id == self.viewer_id)
                                can_admin = true;
                        });
                    }
                });
                return can_admin;
            }
        }

        return false;
    }
});

})(jQuery);
