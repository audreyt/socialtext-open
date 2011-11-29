(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.Widget = function (opts) {
    this.extend(opts);
    this.fetch_limit = Number(this.display_limit) + 10;
    this.requires([
        'share', 'viewer', 'viewer_id', 'static_path',
        'mention_user_id', 'mention_user_name'
    ]);
    this.show_popout = Number(this.show_popout);
};

function isArray() {
    if (typeof arguments[0] == 'object') {  
        var criterion = arguments[0].constructor.toString().match(/array/i);
        return (criterion != null);
    }
    return false;
}

Activities.Widget.prototype = new Activities.Base();

$.extend(Activities.Widget.prototype, {
    toString: function() { return 'Activities.Widget' },

    _defaults: function() { return {
        startText: loc("signals.what-are-you-working-on?"),
        display_limit: 5,
        poll_interval: (3 * 1000)
    }; },

    showDirect: function() {
        var has_show_pref = Number(this.show_direct) && this.direct != 'none';

        // if we're viewing a single signal, we don't want to show direct
        // replies.
        var signal_view = this.signal_id ? 1 : 0;

        return has_show_pref && !signal_view && (this.fixed_feed != 'feed-user');
    },

    show: function(cb) {
        var self = this;
        var template = 'activities/' + self.ui_template;

        self.appdata = new Activities.AppData({
            node: self.node,
            prefix: self.prefix,
            owner: self.owner,
            owner_id: self.owner_id,
            owner_name: self.owner_name,
            group_name: self.group_name,
            viewer: self.viewer,
            instance_id: self.instance_id,
            fixed_action: self.fixed_action,
            fixed_feed: self.fixed_feed,
            fixed_network: self.fixed_network,
            workspace_id: self.workspace_id,
            onSelectSignalToNetwork: function(network) {
                if (self.mainEditor) self.mainEditor.setNetwork(network);
            },
            onRefresh: function() {
                self.forceRefreshEvents();
            }
        });

        self.appdata.load(function() {
            try {
                $(self.node).html(self.processTemplate(template));
                self.appdata.bind();

                if (self.overlap)
                    $(self.node).createSelectOverlap({noPadding: true})

                self.mainEditor = new Activities.Editor({
                    node: $(self.node).find('.mainWikiwyg'),
                    prefix: self.prefix,
                    share: self.share,
                    viewer_id: self.viewer_id,
                    mention_user_id: self.mention_user_id,
                    mention_user_name: self.mention_user_name,
                    static_path: self.static_path,
                    base_uri: self.base_uri,
                    network: self.appdata.getSignalToNetwork(),
                    signal_this: self.signal_this,
                    initial_text: self.initial_text,
                    onPost: function(signal) {
                        if (self.isVisibleSignal(signal)) {
                            self.clearMessages('empty', 'error');
                            self.pushClient.seenSignal(signal.signal_id);
                            var evt = self.eventList.signalToEvent(signal);
                            self.eventList.add(evt);
                            self.eventList.updateDisplay();
                            evt.$node.prependTo(self.eventList.node);
                        }
                        else {
                            self.showMessageNotice({
                                className: 'restrictiveFilters',
                                onCancel: function() {
                                    self.clearMessages('restrictiveFilters');
                                },
                                links: {
                                    '.clearFilters': function() {
                                        self.clearMessages(
                                            'restrictiveFilters'
                                        );
                                        self.resetFiltersForSignal(signal);
                                        return false;
                                    }
                                }
                            })
                        }
                    }
                });
            }
            catch(e) {
                self.showError(e);
                return;
            }

            self.bindHandlers();

            if (self.draggable) $(self.node).draggable(self.draggable);

            if ($.isFunction(cb)) cb();
        });
    },

    resetFiltersForSignal: function(signal) {
        // Unless we're showing all events, select signals
        if (this.appdata.get('action').id != 'action-all-events') {
            this.appdata.checkFilter('action', 'action-signals');
        }

        // show from everyone - not my follows or conversations
        this.appdata.checkFilter('feed', 'feed-everyone');

        // Select the target network unless we're showing all networks
        if (this.appdata.get('network').value != 'all') {
            if (signal.group_ids && signal.group_ids.length) {
                this.appdata.selectNetwork('group-'+signal.group_ids[0]);
            }
            if (signal.account_ids && signal.account_ids.length) {
                this.appdata.selectNetwork('account-'+signal.account_ids[0]);
            }
        }

        this.forceRefreshEvents();
    },

    bindHandlers: function() {
        var self = this;

        /**
         * Signals handlers
         */
        $('.setupWikiwyg').click(function(){
            var $node = $(this);

            if (!$node.hasClass('setting_up')) {
                self.mainEditor.setupWikiwyg();
                $node.addClass('setting_up');
            }
            
            /* reclick once wikiwyg is loaded */
            if (this.tagName.toLowerCase() == 'a') {
                setTimeout(function() { $node.click() }, 600);
            }
            else {
                setTimeout(function() { $node.click() }, 50);
            }

            return false;
        });

        self.setupNotifications();

        this.findId('pop_out').click(function() {
            var poptarget = self.signals_only
                    ? ('/st/signalspop?id=' + self.instance_id)
                    : ('/st/activities?id=' + self.instance_id);
            var new_window = window.open(
                poptarget, '_blank',
                'height=514,width=415,scrollbars=1,resizable=1'
            );
            new_window.focus();
            return false;
        });

        this.findId('more')
            .mouseover(function() { $(this).addClass('hover') })
            .mouseout(function() { $(this).removeClass('hover') })
            .click(function() { self.showMoreEvents(); });
    },

    stop: function() {
        this.pushClient.stop();
        this.pauseTimer();
    },
    
    start: function() {
        var self = this;
        self.show(function() {
            self.eventList = new Activities.EventList({
                prefix: self.prefix,
                node: self.findId('event_list'),
                appdata: self.appdata,
                network: self.appdata.get('network'),
                base_uri: self.base_uri,
                signals_enabled: self.appdata.pluginsEnabled('signals'),
                viewer_id: self.viewer_id,
                owner_id: self.owner_id,
                display_limit: self.display_limit,
                mention_user_id: self.mention_user_id,
                static_path: self.static_path,
                share: self.share,
                onPost: function(signal) {
                    self.pushClient.seenSignal(signal.signal_id);
                },

                // Fully expand permalinks
                minReplies: self.signal_id ? Infinity : 2,
                signal_id: self.signal_id,
                reply_id: self.reply_id
            });

            if (self.signal_id) {
                self.fetchSignal(self.signal_id, function(signal) {
                    // Fully expand the signal
                    signal.max_replies = Infinity;
                    self.eventList.add(signal);
                    self.startTimer({
                        onResume: function() {
                            self.pushClient.start();
                        },
                        callback: function() {
                            self.eventList.updateTimestamps();
                        }
                    });

                    if ($.mobile && $.mobile.silentScrollInitialized) {
                        $.mobile.silentScrollInitialized = false;
                    }

                    self.eventList.updateDisplay();
                    self.startPolling();
                });
            }
            else {
                self.showOlderEvents(true);
                self.startTimer({
                    onResume: function() {
                        self.pushClient.start();
                    },
                    callback: function() {
                        self.showNewerEvents();
                    }
                });
            }
            self.adjustHeight();

            if (self.mainEditor.isVisible()) {
                if (self.fixed_action == 'action-signals' && self.initial_text){
                    $('.mainWikiwyg .setupWikiwyg').click();
                }
            }
        });
    },

    forceRefreshEvents: function() {
        this.eventList.display_limit = this.display_limit; // Reset
        this.eventList.clear();
        this.showOlderEvents(true);
    },

    getEventsURI: function(args) {
        if (!args) args = {};

        // Default params
        $.extend(args, {
            direct: this.direct,
            html: '0',
            link_dictionary: this.link_dictionary
        });

        var network = this.appdata.get('network');
        if (network.group_id) {
            args.group_id = network.group_id;
        } 
        else if (network.account_id) {
            args.account_id = network.account_id;
        } 

        var feed = this.appdata.get('feed');

        // Append event_class!=signal when pushd is running
        var action_filter = this.appdata.get("action");
        var action = action_filter.value;
        if (args.noSignals && action_filter.id == 'action-signals') {
            return null;
        }
        if (args.noSignals) action += ';event_class!=signal';
        delete args.noSignals;

        var url = this.base_uri + '/data/events' + feed.value
                + '?' + action;

        $.each(args, function(key, val) {
            if (val) url += ';' + key + '=' + encodeURIComponent(val);
        });

        return url;
    },

    isVisibleSignal: function(signal) {
        var self = this;
        if (this.signal_id) {
            // In permalink mode, only show replies to the topical signal
            if (signal.signal_id == this.signal_id) return true;
            if (!signal.in_reply_to) return false;
            return signal.in_reply_to.signal_id == this.signal_id;
        }
        
        // Make sure signal is targeting the selected network
        var network = this.appdata.get('network');
        if (signal.recipient) {
            if (!this.showDirect()) return false;
        }
        else if (network.value != 'all') {
            var in_network = (
                ($.grep(signal.account_ids, function(a) { return (a == network.account_id) }).length) ||
                ($.grep(signal.group_ids, function(g) { return (g == network.group_id) }).length)
            );
            if (!in_network) return false;
        }

        // Filter push signals by watchlist
        var feed = this.appdata.get('feed');
        var action = this.appdata.get('action');

        // show mentions on profile pages and in my conversations
        var show_mentions = feed.id == 'feed-user' || (
            feed.id == 'feed-conversations' &&
            (action.id == 'action-all-events' || action.id == 'action-signals')
        )

        if (feed.id == 'feed-followed') {
            if ($.grep(this.watchlist, function(u) { return(u == signal.user_id) }).length == 0) {
                return false;
            }
        }
        else if (show_mentions) {
            if (signal.user_id == self.owner_id) {
                return true;
            }
            if (signal.in_reply_to) {
                if (self.eventList.findSignalIndex(signal.in_reply_to.signal_id) >= 0) {
                    return true;
                }
            }
            if (self.owner_id) {
                var mentioned = $.grep(
                    (signal.mentioned_users || []),
                    function(user) {
                        return(user.id == self.owner_id)
                    }
                );
                if (mentioned.length > 0) {
                    return true;
                }
                if (signal.recipient && (signal.recipient.id == self.owner_id)) {
                    return true;
                }
            }
            return false;
        }

        // Filter push signals by action
        var action = this.appdata.get('action');
        if (action.id == 'action-all-events' || action.id == 'action-signals'){
            return true;
        }

        // filtering by other type of event, so don't show signals
        return false;
    },

    onLog: $.noop,

    startPolling: function() {
        var self = this;

        if (!self.pushClient) {
            self.pushClient = new PushClient({
                nowait: true,
                timeout: self.poll_interval,
                instance_id: self.instance_id,
                onLog: self.onLog,
                onNewSignals: function(signals) {
                    self.clearMessages('empty', 'error');
                    signals = $.grep(signals, function(signal) {
                        return self.isVisibleSignal(signal);
                    });
                    if (signals.length) {
                        self.eventList.add(signals);
                        if (self.eventList.paused()) {
                            self.eventList.showUnreadCount();
                        }
                        else {
                            self.eventList.updateDisplay();
                        }
                        self.showNotifications(signals);
                    }
                },
                onLikeSignals: function(signals) {
                    $.each(signals, function(_, signal) {
                        self.eventList.likeSignal(signal);
                    });
                },
                onUnlikeSignals: function(signals) {
                    $.each(signals, function(_, signal) {
                        self.eventList.unlikeSignal(signal);
                    });
                },
                onHideSignals: function(signals) {
                    self.clearMessages('empty', 'error');
                    $.each(signals, function(i, signal) {
                        self.eventList.removeSignalFromDisplay(signal);
                    });
                },
                onError: function() {
                    self.showError(
                        loc("error.getting-activities")
                    );
                },
                onRefresh: function() {
                    self.showNewerEvents(true);
                }
            });
        }
        self.pushClient.start();
    },

    hasWebkitNotifications: function() {
        return typeof window.webkitNotifications != 'undefined';
    },

    webkitNotificationsEnabled: function() {
        return this.hasWebkitNotifications()
            && window.webkitNotifications.checkPermission() == 0;
    },

    webkitNotificationsDisabled: function() {
        return this.hasWebkitNotifications()
            && window.webkitNotifications.checkPermission() > 0;
    },

    setupNotifications: function() {
        var self = this;

        // Insert a link to enable Desktop notifications... yeah, this is a
        // bit hacky, but there isn't an opensocial way of doing this.
        if (self.webkitNotificationsDisabled()) {
            var $setup = $('#'+self.instance_id+'-setup');
            $setup.find('select[name=notify]').parent().append(
                self.processTemplate('enable_notifications_link')
            );
        }

        if (self.notify_preference == 'never') return;

        // If we aren't using chrome notifications, use the window title
        // instead
        if (!self.webkitNotificationsEnabled()) {
            var toggle = false;
            self._originalTitle = $('title').text() || document.title;
            setInterval(function() {
                var title = self.signalCount
                    ? loc('activities.title=signal-count,original-title', self.signalCount, self._originalTitle)
                    : self._originalTitle;

                if (toggle && self.mentionCount) {
                    title = loc(
                        'activities.new-mentions=count', self.mentionCount
                    );
                }

                try { $('title').text(title) } catch (e) {};
                try { document.title = title } catch (e) {};
                toggle = !toggle;
            }, 3000);
        }

        // clear existing notifications
        self.popups = [];
        $(window).focus(function() {
            self.clearNotifications();
        });
    },

    clearNotifications: function() {
        $('title').text(self._originalTitle);
        $.each(this.popups, function(i, popup) {
            popup.cancel();
        });
        this.popups = [];
        this.mentionCount = 0;
        this.signalCount = 0;
    },

    showNotifications: function(signals) {
        var self = this;

        // don't show notifications if the window is focused
        if (document.hasFocus()) return;

        // ... or if the preference is turned off
        if (self.notify_preference == 'never') return;

        $.each(signals, function(i, signal) {
            var in_reply_to = signal.in_reply_to || {};
            var recipient = signal.recipient || {};
            var mention = false;

            // Private message to us:
            if (recipient && recipient.id == self.owner_id) {
                mention = true;
            }
            // I was mentioned:
            else {
                $.each(signal.mentioned_users || [], function(i, user) {
                    if (user.id == self.owner_id) mention = true;
                });
            }

            if (mention) {
                self.showNotification(signal, true);
            }
            else if (self.notify_preference == 'always') {
                self.showNotification(signal, false);
            }
        });
    },

    showNotification: function(signal, mention) {
        var self = this;
        if (self.webkitNotificationsEnabled()) {
            var targets = self.eventList.signalTargets(signal);
            var title = signal.recipient
                ? loc('activities.private-to-you=sender', signal.best_full_name)
                : loc(
                    'activities.to=sender,targets', signal.best_full_name,
                    targets.join(', ')
                  );
            var popup = window.webkitNotifications.createNotification(
                self.base_uri + "/data/people/" + signal.user_id + "/photo",
                title,
                signal.body.replace(/<[^>]+>/g, '') // Strip HTML tags
            );
            self.popups.push(popup);
            popup.show();
            $(popup).click(function() {
                $(window).focus();
                self.clearNotifications();
            });

            // if this is not a mention, hide it after 7 seconds
            if (!mention) setTimeout(function() { popup.cancel() }, 7000);
        }
        else {
            if (!self.mentionCount) self.mentionCount = 0;
            if (!self.signalCount) self.signalCount = 0;
            if (mention) self.mentionCount++;
            self.signalCount++;
        }
    },

    stopPolling: function() {
        if (this.pushClient) {
            this.pushClient.stop();
        }
    },

    requestEvents: function(uri, callback, force) {
        var self = this;
        if (!this.findId('event_list').size()) return;
        if (this._inRequest) return;
        this._inRequest = true;

        if (force) {
            this.startPolling();
        }

        this.clearMessages('empty', 'error');
        this.makeRequest(uri, function(data) {
            self.findId('loading').remove();
            if (!data.data || data.errors.length > 0) {
                self.showError(
                    loc("error.getting-activities")
                );
                self.eventList.updateTimestamps();
                self.adjustHeight();
                self._inRequest = false;
                return;
            }
            if (!self.findId('event_list .event').size() && !data.data.length) {
                self.showEmptyMessage();
                self._inRequest = false;
                return;
            }

            var events = data.data;

            // Add a replies array to each event
            $.each(events, function(i, evt) { evt.replies = [] });

            self._inRequest = false;

            callback(events);

            self.eventList.updateTimestamps();
            self.adjustHeight();
        }, force);
    },

    fetchSignal: function(signal_id, callback) {
        var self = this;
        var uri = this.base_uri + '/data/signals/' + signal_id;
        this.makeRequest(uri, function(data) {
            self.findId('loading').remove();
            if ($.isFunction(callback)) callback(data.data);
        }, true);
    },

    showOlderEvents: function(force) {
        var self = this;

        var uri = self.getEventsURI({
            before: self.eventList.oldest(),
            limit: self.fetch_limit,
            noSignals: !force
        });
        if (!uri) return;

        self.requestEvents(uri, function(events) {
            if (events.length) {
                // add these to events
                self.eventList.add(events);
            }

            self.eventList.updateDisplay();

            var filtered_length = self.eventList.filteredEvents().length;

            if (events.length < self.fetch_limit) {
                // NO MORE EVENTS ON SERVER
                if (filtered_length < self.eventList.display_limit) {
                    self.findId('more').hide();
                }
                else {
                    self.findId('more').show();
                }
            }
            else {
                // SERVER MAY HAVE MORE EVENTS
                // events.length == self.fetch_limit
                if (filtered_length <= self.eventList.display_limit) {
                    self.showOlderEvents(force);
                }
                else {
                    self.findId('more').show();
                }
            }
        }, force);
    },

    showNewerEvents: function(force) {
        var self = this;

        // {bz: 4331}: Need to update timestamps here, in case the "uri"
        // below is null for AWid setting to showing "signals" only.
        self.eventList.updateTimestamps();

        var uri = self.getEventsURI({
            after: self.eventList.newest(),
            limit: self.fetch_limit,
            noSignals: !force
        });
        if (!uri) return;

        self.requestEvents(uri, function(events) {
            if (events.length) {
                events.reverse();
                self.eventList.add(events);

                if (self.eventList.paused() && !force) {
                    self.eventList.showUnreadCount();
                }
                else {
                    self.eventList.updateDisplay();
                }
            }
        }, force);
    },

    showMoreEvents: function() {
        this.eventList.display_limit
            = Number(this.eventList.display_limit) + 5;
        var filtered_length = this.eventList.filteredEvents().length;
        if (filtered_length > this.eventList.display_limit) {
            this.eventList.updateDisplay();
        }
        else {
            this.showOlderEvents(true);
        }
    },

    signalReplies: function(evt) {
        if (!evt.replies) return [];
        return evt.replies.slice(- this.repliesToShow(evt));
    },

    repliesToShow: function(evt) {
        if (typeof(evt.max_replies) == 'undefined') evt.max_replies = 2;
        return evt.replies.length > evt.max_replies
            ? evt.max_replies : evt.replies.length;
    },

    showEmptyMessage: function() {
        var feed = this.appdata.getValue('feed');
        this.addMessage({
            className: 'empty',
            html: this.processTemplate('activities/empty.tt2', {
                feed: this.appdata.get('feed'),
                action: this.appdata.get('action')
            })
        });
        this.findId('more').hide();
        this.adjustHeight();
    },

    timerName: function() {
        return this.prefix + '-timer';
    },

    startTimer: function(cb) {
        if (!cb) this.showError("no callbacks!");
        this._timer_callbacks = cb;
        $('body').everyTime('30s', this.timerName(), function(){ cb.callback() });
    },

    resumeTimer: function() {
        var cb = this._timer_callbacks;
        if (!cb) this.showError("no callbacks!");
        if (cb.onResume) cb.onResume();
        this.startTimer(cb);
    },

    pauseTimer: function() {
        $('body').stopTime(this.timerName());
    }

});

})(jQuery);
