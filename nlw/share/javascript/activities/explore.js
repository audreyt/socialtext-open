(function($) {

if (typeof(Activities) == 'undefined') Activities = {};

Activities.Explore = function(opts) {
    this.extend(opts);
    this.requires([ ]);
}

Activities.Explore.prototype = new Activities.Base();

$.extend(Activities.Explore.prototype, {
    toString: function() { return 'Activities.Explore' },

    _defaults: {
        assets: [],
        emptyMessage: loc('error.no-items-for-explore'),
        limit: 15,
        offset: 0
    },

    start: function() {
        var self = this;

        self.appdata = new Activities.AppData({
            node: self.node,
            fields: [ 'never_again' ],
            prefix: self.prefix,
            user: self.owner || self.viewer,
            instance_id: self.instance_id,
            viewer: self.viewer,
            owner: self.owner,
            owner_id: self.owner_id,
            fixed_action: self.fixed_action,
            fixed_feed: self.fixed_feed,
            fixed_network: 'all',
            onSelectSignalToNetwork: function(network) {
            },
            onRefresh: function() {
            }
        });

        self.appdata.load(function() {
            var neverAgain = Number(self.appdata.get('never_again'));
            if (!neverAgain) self.showAboutBox();

            self.getAssets();
            Activities.ExploreFilters.onChange(function(modified) {
                self.getAssets();
            });
            self.startPolling();
        });
    },

    showAboutBox: function() {
        var self = this;
        get_plugin_lightbox('signals', 'explore-about', function () {
            var lightbox = new ST.ExploreAbout;
            lightbox.show({
                show_never_again: true
            });
            $('#explore-about-never-again').click(function() {
                if ($(this).is(':checked')) {
                    self.appdata.save('never_again', 1);
                }
                else {
                    self.appdata.save('never_again', 0);
                }
            });
        });
    },

    loading: function() {
        var $node = $(this.node);
        var offset = $node.offset();
        $('#assetOverlay')
            .height($node.height() > 300 ? $node.height() : 300)
            .width($node.width())
            .css({
                'top': offset.top,
                'left': offset.left
            })
            .show();
    },

    doneLoading: function() {
        $('#assetOverlay').hide();
    },

    getAssets: function() {
        var self = this;

        self.offset = 0;

        self.loading();
        var uri = Activities.ExploreFilters.uri({
            limit: self.limit + 1
        });
        self.makeRequest(uri, function(data) {
            self.doneLoading();
            self.assets = data.data || [];

            // update tag colors
            self.setTagColors(self.assets);

            // Check if there are more
            self.moreAssets = self.assets.length > self.limit;
            if (self.moreAssets) self.assets.pop();

            var vars = { assets: self.assets };

            $(self.node).html(
                self.processTemplate('activities/assets.tt2', vars)
            ); 
            if (self.assets.length) {
                self.updateCountColors();
                self.bindAssetHandlers();
                if (Activities.ExploreFilters.getValue('order') == 'recency'){
                    self.groupTimeframes();
                }
            }
            else {
                self.addMessage({ className:'empty', html:self.emptyMessage });
            }
        });
    },

    getMoreAssets: function() {
        var self = this;

        self.offset += self.limit;

        var uri = Activities.ExploreFilters.uri({
            limit: self.limit + 1,
            offset: self.offset
        });

        // Replace the more button with a loading icon
        $('.moreAssetsLoading').show();
        $('.moreAssets').hide();

        self.makeRequest(uri, function(data) {
            // hide the loading icon
            $('.moreAssetsLoading').hide();

            var assets = data.data || [];

            // update tag colors
            self.setTagColors(assets);

            // Check if there are more
            self.moreAssets = assets.length > self.limit;
            if (self.moreAssets) {
                assets.pop();
                $('.moreAssets').show();
            }

            $.each(assets, function(i, asset) {
                $('.assetList').append(
                    self.processTemplate('asset', {
                        asset: asset,
                        index: self.assets.length
                    })
                );
                self.assets.push(asset);
            });

            self.updateCountColors();
            self.bindAssetHandlers();
            if (Activities.ExploreFilters.getValue('order') == 'recency'){
                self.groupTimeframes();
            }
        });
    },

    groupTimeframes: function() {
        var self = this;

        var n = new Date(); // now
        var timeframes = [
            {
                name: loc('explore.today'),
                after: new Date(n.getFullYear(), n.getMonth(), n.getDate())
            },
            {
                name: loc('explore.past-week'),
                after: new Date(n.getFullYear(), n.getMonth(), n.getDate() - 7)
            },
            {
                name: loc('explore.past-month'),
                after: new Date(n.getFullYear(), n.getMonth() - 1, n.getDate())
            },
            {
                name: loc('explore.past-year'),
                after: new Date(n.getFullYear() - 1, n.getMonth(), n.getDate())
            },
            {
                name: loc('explore.oldies'),
                after: new Date(0)
            }
        ];

        $('.timeframe', self.node).remove();
        $('.empty', self.node).remove();

        var timeframe = timeframes.shift();
        $.each(self.assets, function(i, asset) {
            // Parse date
            var parts = asset.latest.substr(0,10).split('-');
            var day = new Date(parts[0], parts[1]-1, parts[2]);

            if (day.getTime() >= timeframe.after.getTime()) {
                // This signal is in this timeframe

                // Add the timeframe splitter before this asset
                if (!timeframe.node) self.addTimeframe(timeframe, asset);
            }
            else {
                if (!timeframe.node) {
                    // Add an empty timeframe splitter before this asset
                    self.addTimeframe(timeframe, asset);
                    $('<div class="empty"></div>')
                        .html(loc("explore.no-items"))
                        .insertAfter(timeframe.node);
                }

                // Find next timeframe
                while (day.getTime() < timeframe.after.getTime()) {
                    timeframe = timeframes.shift();
                }
                self.addTimeframe(timeframe, asset);
            }
        });
    },

    addTimeframe: function(timeframe, asset) {
        timeframe.node = $('<fieldset class="timeframe"></fieldset>')
            .append('<legend>' + timeframe.name + '</legend>')
            .insertBefore(asset.node);
    },

    bindAssetHandlers: function() {
        var self = this;
        $.each(self.assets, function(i, asset) {
            if (asset.node) return; // skip already displayed 
            if (typeof(asset.signals) == 'undefined') asset.signals = [];
            asset.node = self.findId('asset' + i);
            asset.eventList = new Activities.EventList({
                prefix: self.prefix,
                node: asset.node.find('.event_list'),
                owner_id: self.owner_id,
                minReplies: 1,
                appdata: self.appdata,
                static_path: self.static_path,
                share: self.share.replace('signals','widgets'),
                signals_enabled: true,
                base_uri: self.base_uri,
                viewer_id: self.viewer_id,
                display_limit: Infinity,
                onPost: function(signal) {
                    self.pushClient.seenSignal(signal.signal_id);
                }
            });

            asset.eventList.add(asset.signals, true);
            asset.eventList.updateDisplay();

            asset.node.find('.count, .expand a').click(function() {
                self.toggleMentions(asset);
                return false;
            });
        });

        $(self.node).find('.more')
            .mouseover(function() { $(this).addClass('hover') })
            .mouseout(function() { $(this).removeClass('hover') })
            .click(function() { self.getMoreAssets() });
    },

    // update tag colors
    setTagColors: function(assets) {
        $.each(assets, function(i, asset) {
            // Count duplicate tags and fine the most duplicated tag
            var tags = {};
            var highest = 0;
            $.each(asset.tags, function(j, tag) {
                if (!tags[tag]) tags[tag] = 0;
                tags[tag]++;
                if (tags[tag] > highest) highest = tags[tag];
            });

            // Now create a sorted array of tag hashes that includes color
            asset.unique_tags = [];
            $.each(tags, function(tag, count) {
                var dec = Math.round((highest - count) / highest * 200);
                asset.unique_tags.push({
                    name: tag,
                    count: count,
                    color: 'rgb(' + [dec,dec,dec].join(',') + ')'
                });
            });
        });
    },
    
    // Produce a value between rgb(0,0,0) and rgb(214,214,214)
    updateCountColors: function() {
        var self = this;
        
        // Get the highest count value
        var counts = $.map(this.assets, function(a) { return Number(a.count) });
        var highest = counts.sort(function(a, b) { return a > b }).pop();

        $.each(self.assets, function(i, asset) {
            var dec = Math.round((highest - asset.count) / highest * 214);
            self.findId('asset' + i).find('.count').css(
                'background-color', 'rgb(' + [dec,dec,dec].join(',') + ')'
            );
        });
    },

    toggleMentions: function(asset) {
        asset.expanded = !asset.expanded;
        if (asset.expanded) {
            asset.node.find('.arrow.right, .expand').hide();
            asset.node.find('.arrow.down').show();
            asset.node.find('.assetBody').show();
            if (!asset.eventList.events.length) this.getMoreSignals(asset);
        }
        else {
            asset.node.find('.arrow.down').hide();
            asset.node.find('.arrow.right, .expand').show();
            asset.node.find('.assetBody').hide();
        }

        asset.node.find('.count').attr(
            'title', this.processTemplate('count_title', { asset: asset })
        );
    },

    addReplies: function(replies) {
        var self = this;
        $.each(replies, function(i, reply) {
            if (reply.in_reply_to) {
                $.each(self.assets, function(j, asset) {
                    if (asset.eventList.contains(reply.in_reply_to.signal_id)){
                        asset.eventList.add(reply);
                        if (asset.eventList.paused()) {
                            asset.eventList.showUnreadCount();
                        }
                        else {
                            asset.eventList.updateDisplay();
                        }
                    }
                });
            }
        });
    },
    
    startPolling: function() {
        var self = this;

        if (!self.pushClient) {
            self.pushClient = new PushClient({
                nowait: true,
                timeout: 3000,
                //onLog: function(msg) { console.log(msg) },
                onNewSignals: function(signals) {
                    self.addReplies(signals);
                },
                onHideSignals: function(signals) {
                    $.each(signals, function(i, signal) {
                        self.removeSignal(signal.signal_id);
                    });
                }
            });
        }
        self.pushClient.start();
    },

    // Iterate over each asset removing it from each eventlist
    removeSignal: function(signal_id) {
        var self = this;
        $.each(self.assets, function(i, asset) {
            asset.eventList.removeSignalFromDisplay(signal_id);
        })
    },

    getMoreSignals: function(asset) {
        var self = this;

        var ids = asset.signal_ids.splice(0, 5);
        if (!ids.length) return;

        var uri = self.base_uri + '/data/signals/' + ids.join(',');
        self.makeRequest(uri, function(data) {
            if (data.errors.length) {
                self.showError(data.errors[0]);
            }
            else {
                // this could be a single signal or an array of signals
                var signals = data.data instanceof Array
                    ? data.data : [ data.data ];
                asset.eventList.add(signals, true);
                asset.eventList.updateDisplay();

                // show the more button if there are more
                if (asset.signal_ids.length) {
                    asset.node.find('.moreMentions').show();
                }
            }

            asset.node.find('.moreMentions a').click(function() {
                asset.node.find('.moreMentions').hide();
                self.getMoreSignals(asset);
                return false;
            });
        });
    }
});

})(jQuery);
