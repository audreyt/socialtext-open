(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.AppData = function(opts) {
    this.extend(opts);
    this.requires([
        'instance_id', 'owner', 'viewer', 'owner_id'
    ]);
}

Activities.AppData.prototype = new Activities.Base()

$.extend(Activities.AppData.prototype, {
    toString: function() { return 'Activities.AppData' },

    _defaults: {
        fields: [ 'sort', 'network', 'action', 'feed', 'signal_network' ]
    }, 

    load: function(callback) {
        var self = this;

        var opensocial = rescopedOpensocialObject(self.instance_id);

        var getReq = opensocial.newDataRequest();
        var viewer = opensocial.newIdSpec({
            "userId" : opensocial.IdSpec.PersonId.VIEWER
        });
        getReq.add(
            getReq.newFetchPersonAppDataRequest(viewer, self.fields), "get_data"
        );

        var user = self.owner || self.viewer;

        getReq.add(
            new RestfulRequestItem(
                '/data/users/' + user + '?minimal=1', 'GET', null
            ), 'get_user'
        );

        getReq.add(
            new RestfulRequestItem(
                '/data/people/' + user + "/watchlist", 'GET', null
            ), 'get_watchlist'
        );

        getReq.send(function(dataResponse) {
            var appDataResult = dataResponse.get('get_data');
            if (appDataResult.hadError()) {
                self.showError(
                    "There was a problem getting user preferences"
                );
                return;
            }
            self.appData = appDataResult.getData();

            var userDataResult = dataResponse.get('get_user');
            if (userDataResult.hadError()) {
                self.showError(
                    "There was a problem getting user data"
                );
                return;
            }
            self.user_data = userDataResult.getData();

            var watchlistResult = dataResponse.get('get_watchlist');
            if (userDataResult.hadError()) {
                self.showError(
                    "There was a problem getting watchlist"
                );
                return;
            }
            var watchlistResultData = watchlistResult.getData();
            if (watchlistResultData) {
                self.watchlist = $.map(watchlistResult.getData(), function(u) {
                    return u.id;
                });
            }
            else {
                self.watchlist = [];
            }
            callback();
        });
    },

    save: function(key, val) {
        var self = this;
        self.appData[key] = val;

        // if instance_id == 0, we're somewhere like the signal-this popup
        if (!Number(self.instance_id)) return;

        var opensocial = rescopedOpensocialObject(self.instance_id);

        var setReq = opensocial.newDataRequest();
        setReq.add(
            setReq.newUpdatePersonAppDataRequest(
                opensocial.IdSpec.PersonId.VIEWER, key, val 
            ), 'set_data'
        );
        setReq.send(function(dataResponse) {
            if (dataResponse.hadError())  {
                self.showError(
                    "There was a problem setting user preferences"
                );
                return;
            }
            var dataResult = dataResponse.get('set_data');
            if (dataResult.hadError()) {
                self.showError(
                    "There was a problem setting user preferences"
                );
                return;
            }
        });
    },

    isBusinessAdmin: function() {
        return Number(this.user_data.is_business_admin);
    },

    accounts: function() {
        return this.user_data.accounts;
    },

    groups: function() {
        return this.user_data.groups;
    },

    getDefaultFilter: function(type) {
        var list = this.getList(type);
        var matches = $.grep(list, function(item) {
            return item['default'];
        });
        if (matches.length) return matches[0];
    },

    getList: function(key) {
        if (key == 'network' || key == 'signal_network') {
            return this.networks();
        }
        else if (key == 'action') {
            return this.actions();
        }
        else if (key == 'feed') {
            return this.feeds();
        }
    },

    getById: function(type, id) {
        var list = this.getList(type);
        var matches = $.grep(list, function(item) {
            return item.id == id;
        });
        if (matches.length) return matches[0];
    },

    getByValue: function(type, value) {
        var list = this.getList(type);
        var matches = $.grep(list, function(item) {
            return item.value == value;
        });
        if (matches.length) return matches[0];
    },

    isShowingSignals: function () {
        return this.get('action').signals;
    },

    get: function(type) {
        var list = this.getList(type);

        // Check the appdata value
        var value = this['fixed_' + type] || this.appData[type];

        if (!list) return value;

        if (value) {
            // Value was either present in a cookie or pref, so return it
            var filter = this.getByValue(type, value)
                      || this.getById(type, value);
            if (filter) return filter;
        }

        // No value is set, so just use the first, default first
        list = list.slice();
        list.sort(function(a,b) {
            return a['default'] ? -1 : b['default'] ? 1 : 0;
        })
        return list[0];
    },

    getValue: function(type) {
        var filter =  this.get(type);
        if (!filter) throw new Error("Can't find filter value for " + type);
        return filter.value;
    },

    set: function(type, value) {
        if (!this.getById(type,value)) {
            throw new Error(
                "Invalid filter type or value: " + type + ':' + value
            );
        }
        this.save(type, value);
    },

    sortNetworks: function(networks) {
        function name_sort(a,b) {
            var a_name = a.name || a.account_name;
            var b_name = b.name || b.account_name;
            return a_name.toUpperCase().localeCompare(b_name.toUpperCase());
        };
        return networks.sort(name_sort);
    },

    networks: function() {
        var self = this;
        if (self._networks) return self._networks;

        var prim_acc_id = self.user_data.primary_account_id
        var sorted_accounts = self.sortNetworks(self.user_data.accounts);
        var sorted_groups = self.sortNetworks(self.user_data.groups);

        var networks = [];

        // Check for a fixed value
        $.each(sorted_accounts, function(i, acc) {
            var primary = acc.account_id == prim_acc_id ? true : false;
            var userlabel = (acc.user_count == 1) ? ' user)': ' users)';
            var additional = primary
                ? loc('signals.primary-account=users', acc.user_count)
                : loc('signals.network-count=users', acc.user_count);


            $.extend(acc, {
                'default': primary,
                value: 'account-' + acc.account_id,
                id: 'account-' + acc.account_id,
                title: acc.account_name + ' ' + '(' + additional + ')',
                filterTitle: acc.account_name + ' '
                    + '<div class="users">' + additional + '</div>',
                wrap: true,
                signals_size_limit:
                    acc.plugin_preferences.signals.signals_size_limit
            });

            if (self.isCurrentNetwork(acc.value)) {
                networks.push(acc);
                acc.num_groups = 0;
            }

            // Now find the groups in that account
            $.each(sorted_groups, function(i, grp) {
                if (grp.primary_account_id == acc.account_id) {
                    acc.num_groups++;
                    var additional = loc(
                        'signals.network-count=users', grp.user_count
                    );
                    var title = grp.name + ' (' + additional + ')';
                    $.extend(grp, {
                        value: 'group-' + grp.group_id,
                        id: 'group-' + grp.group_id,
                        optionTitle: '... ' + title,
                        title: title,
                        filterTitle: grp.name
                            + ' <div class="users">' + additional + '</div>',
                        signals_size_limit: acc.signals_size_limit,
                        plugins_enabled: acc.plugins_enabled
                    });
                    if (self.isCurrentNetwork(grp.value)) {
                        networks.push(grp);
                    }
                }
            });
        });

        // Add an option for all networks if there's more than one network
        if (networks.length == 0 && self.fixed_network) {
            networks = [
                {
                    value: self.fixed_network,
                    id: self.fixed_network,
                    title: this.group_name,
                    group_id: Number(self.fixed_network.replace(/group-/,'')),
                    plugins_enabled: []
                }
            ];
        }
        else if (networks.length > 1) {
            var title = this.owner == this.viewer
                      ? loc('activities.all-my-groups')
                      : loc('activities.all-shared-groups');
            networks.unshift({
                value: 'all',
                id: 'network-all',
                title: title,
                plugins_enabled: ['signals'],

                // Get the shortest signals_size_limit to set as limit
                // for all networks
                signals_size_limit: $.map(sorted_accounts, function(a) {
                    return a.signals_size_limit;
                }).sort(function (a, b){ return a-b }).shift()
            });
        }

        return this._networks = networks;
    },

    isCurrentNetwork: function(net) {
        return !this.fixed_network
            || this.fixed_network == 'all'
            || this.fixed_network == net;
    },

    signalToOptions: function() {
        var self = this;
        if (self._signal_accounts) return self._signal_accounts;

        var accounts = [];
        $.each(self.sortNetworks(self.user_data.accounts), function(i, acc) {
            if (!~$.inArray('signals', acc.plugins_enabled)) return;

            // clone and push
            var section = { title: acc.account_name, networks: [] };
            accounts.push(section);

            // Add all the target networks
            $.each(self.networks(), function(i, net) {
                var account_id = net.primary_account_id || net.account_id;
                if (account_id == acc.account_id) {
                    section.networks.push(net);
                }
            });
        });

        return self._signal_accounts = accounts;
    },

    actions: function() {
        var self = this;
        if (self._actions) return self._actions;

        var all_events = {
            error_title: loc('activities.events'),
            title: loc('activities.all-events'),
            value: "activity=all-combined;with_my_signals=1",
            signals: true,
            'default': true,
            id: "action-all-events"
        };

        // {bz: 3950} - Don't show person events on the group homepage
        if (self.fixed_network) {
            all_events.value += ";event_class!=person";
        }

        var actions = [
            all_events,
            {
                title: loc('activities.signals'),
                value:"action=signal,edit_save,comment;signals=1;with_my_signals=1",
                id: "action-signals",
                signals: true,
                skip: !self.pluginsEnabled('signals', 'people')
            },
            {
                title: loc('activities.contributions'),
                value: "event_class=page;contributions=1;with_my_signals=1",
                id: "action-contributions"
            },
            {
                title: loc('activities.edits'),
                value: "event_class=page;action=edit_save",
                id: "action-edits"
            },
            {
                title: loc('activities.comments'),
                value: "event_class=page;action=comment",
                id: "action-comments"
            },
            {
                title: loc('activities.page-tags'),
                value: "event_class=page;action=tag_add,tag_delete",
                id: "action-tags"
            },
            {
                title: loc('activities.people-events'),
                value: "event_class=person" ,
                id: "action-people-events",
                skip: !self.pluginsEnabled('people')
            }
        ];

        // Check for a fixed value
        if (self.fixed_action) {
            actions = $.grep(actions, function(action) {
                return action.value == self.fixed_action
                    || action.id == self.fixed_action;
            });
        }

        return this._actions = actions;
    },

    feeds: function() {
        var self = this;
        if (self._feeds) return self._feeds;
        var feeds = [
            {
                title: loc('activities.everyone'),
                value: '',
                id: "feed-everyone",
                signals: true,
                'default': true
            },
            {
                title: loc('activities.following'),
                value: "/followed/" + self.viewer,
                id: "feed-followed",
                signals: true,
                skip: self.pluginsEnabled('people')
            },
            {
                title: loc('activities.my-conversations'),
                value: "/conversations/" + self.viewer,
                id: "feed-conversations"
            }
        ];

        if (self.owner) {
            feeds.push({
                hidden: true,
                title: (self.viewer == self.owner) ? loc('activities.me') : (self.owner_name || 'Unknown User'),
                value: '/activities/' + self.owner_id,
                signals: true,
                id: 'feed-user'
            });
        }

        // Check for a fixed value
        if (self.fixed_feed) {
            feeds = $.grep(feeds, function(feed) {
                return feed.value == self.fixed_feed
                    || feed.id == self.fixed_feed;
            });
        }

        return this._feeds = feeds;
    },

    getSignalToNetwork: function () {
        if (this._signalToNetwork) {
            return this.getByValue('network', this._signalToNetwork);
        }
        else {
            return this.get('network');
        }
    },

    pluginsEnabled: function() {
        var self = this;
        // Build a list of enabled plugins
        if (typeof(self._pluginsEnabled) == 'undefined') {
            self._pluginsEnabled = {};
            $.each(self.networks(), function(i, network) {
                // don't consider the fake "-all" network (which always
                // forces a fixed set of plugins)
                if (network.id == 'network-all') return;
                $.each(network.plugins_enabled, function(i, plugin) {
                    self._pluginsEnabled[plugin] = true;
                });
            });
        }

        var enabled = true;
        $.each(arguments, function(i, plugin) {
            if (!self._pluginsEnabled[plugin]) enabled = false;
        });
        return enabled;
    },

    updateFilterText: function() {
        // update text (but after this handler completes)
        this.findId('expander').html(loc(
            'activities.showing=action,feed,group',
            ('<span class="filter">' + this.get('action').title + '</span>'),
            ('<span class="filter">' + this.get('feed').title + '</span>'),
            ('<span class="filter last">' + this.get('network').title + (
            this.findId('filters').is(':visible')
                ? '<span class="ui-icon ui-icon-circle-triangle-s"></span>'
                : '<span class="ui-icon ui-icon-circle-triangle-e"></span>'
            ) + '</span>')
        ));
    },

    bind: function() {
        var self = this;

        $.each(['action', 'feed', 'network'], function(_,type) {
            $(self.node).find('input.'+type)
                .click(function() {
                    if (self.getValue(type) != $(this).attr('id')) {
                        self.set(type, $(this).attr('id'));
                    }
                    self.checkDisabledOptions();
                    if (self.onRefresh) self.onRefresh();
                })
                .change(function() {
                    $(self.node).find('input.'+type)
                        .parents('.filterOption')
                        .removeClass('selectedOption');
                    $(this).parents('.filterOption')
                        .addClass('selectedOption');

                    if (type == 'network') {
                        self.selectSignalToNetwork($(this).val());
                    }

                    // update text (but after this handler completes)
                    setTimeout(function() { self.updateFilterText() }, 0);
                });
        });
        self.findId('filters').find('input:checked').change();

        var fixed_network = Boolean(
            self.fixed_network || self.networks().length <= 1
        );
        var signal_network = self.get('signal_network');
        if (signal_network) {
            self.findId('signal_network')
                .html(
                    self.processTemplate('network_options', {
                        options: self.signalToOptions()
                    })
                )
                .dropdown()
                .change(function() {
                    self.selectSignalToNetwork($(this).val());
                });

            self.selectSignalToNetwork(signal_network.value);
        }

        self.findId('expander').toggle(
            function() {
                self.findId('filters').show();
                if (typeof TouchScroll != 'undefined') { try {
                    self.findId('filters').data('scroller', new(TouchScroll())(
                        self.findId('filters').find('.scrolling').get(0)
                    ));
                    window.scrollTo(0, self.findId('filters').parent("div.filter_bar").offset().top);
                } catch (e) {} }
                self.updateFilterText();
                return false;
            },
            function() {
                if (window.TouchScrollStop) {
                    window.TouchScrollStop();
                    var scroller = self.findId('filters').data('scroller');
                    scroller.scrollTo(0, 0);
                }
                self.findId('filters').hide();
                self.updateFilterText();
                return false;
            }
        );

        self.findId('close').click(function() {
            self.findId('expander').click();
            return false;
        });

        self.checkDisabledOptions();
    },

    checkDisabledOptions: function() {
        var self = this;
        var action = $(self.node).find('input.action:checked').attr('id');
        var feed = $(self.node).find('input.feed:checked').attr('id');
        if (!feed || !action) return;
        var not_conversations = {
            'action-tags' : 1,
            'action-people-events' : 1
        };

        $(self.node)
            .find('input.action, input.feed, input.network')
            .removeAttr('disabled')
            .parents('.filterOption').removeClass('disabledOption');

        if (not_conversations[action]) {
            $(self.node)
                .find('input.feed#feed-conversations')
                .attr('disabled', 'disabled')
                .parents('.filterOption').addClass('disabledOption');
        }
        if (feed == 'feed-conversations') {
            $.each(this.actions(), function(i, option) {
                if (not_conversations[option.id]) {
                    $(self.node)
                        .find('input.action#' + option.id)
                        .attr('disabled', 'disabled')
                        .parents('.filterOption').addClass('disabledOption');
                }
            });
        }
    },

    checkFilter: function(key, id) {
        var $inputs = this.findId('filters').find('.' + key);
        var $option = $inputs.filter('#'+id);

        // Don't change anything if $option doesn't exist or is already
        // checked
        if (!$option.size() || $option.is(':checked')) return;

        $inputs.removeAttr('checked');
        this.set(key, id);
        this.checkDisabledOptions();
        $option.attr('checked', 'checked').change();
    },

    selectNetwork: function(network_id) {
        if (this.getValue('network') != network_id) {
            this.set('network', network_id);
        }

        if (this.findId('signals').size() && network_id != 'network-all') {
            this.selectSignalToNetwork(network_id);
        }

        this.checkFilter('network', network_id);

        this.findId('groupscope').text(this.get('network').title);
    },

    selectSignalToNetwork: function (network_id) {
        if (network_id == 'all') return;

        if (this.getValue('signal_network') != network_id) {
            this.set('signal_network', network_id);
        }
        if (this.findId('signal_network').val() != network_id) {
            this.findId('signal_network').dropdownSelectValue(network_id);
        }

        var network = this.getById('network', network_id);
        this._signalToNetwork = network_id;
        this.findId('signal_network').val(network_id);
        if ($.inArray('signals', network.plugins_enabled) == -1) {
            this.findId('signals').hide(); 
        }
        else {
            this.findId('signals').show(); 
            this.findId('signal_network').val(network_id);
            this._signalToNetwork = network_id;
            this.onSelectSignalToNetwork(network);
        }
    }

});

})(jQuery);
