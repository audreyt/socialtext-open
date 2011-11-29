(function($){

TopContent = function(args) {
    var self = this;
    $.extend(self, args);
    if (!self.prefs) throw new Error("Prefs object required!!");
    self.showMessage(loc('widgets.loading'));
    jQuery(window).bind('resize', function() { self.fixWidths() });
};

TopContent.prototype = {
    id: function(raw_id) {
        return this.module_id + raw_id;
    },

    render: function(opts) {
        var self = this;
        if (typeof(opts) == 'undefined') opts = {};
        $.extend(opts, {
            id: function(id) { return self.id(id) },
            loc: loc
        });
        $(self.node).html(Jemplate.process('top_content.tt2', opts));
    },

    showMessage: function(message) {
        this.render({ message: message });
    },

    display: function() {
        var self   = this;
        var prefs  = self.prefs;
        self.rotating = prefs.getBool('rotate');
        self.fetchData();
        if (self.rotating) {
            self.startTimer();
        }
        else {
            self.stopTimer();
        }
    },

    // check for cached data first, if it's there, use that.
    // if not, then we'll hit our server and cache what it returns.
    fetchData: function() {
        var self = this;
        var action = this.action || this.default_tab;

        if (!this.tabs[action])
            action = this.default_tab;

        if (!this.tabs[action])
            throw new Error("No action named " + action);

        if ( this.tabs[action].data ) {
            this.showData( action );
        }
        else {
            var params = {};
            params[gadgets.io.RequestParameters.HEADERS] = {
                'Content-Type' : 'application/json'
            };
            params[gadgets.io.RequestParameters.CONTENT_TYPE] =
                gadgets.io.ContentType.JSON;
            // The reports cron jobs run every 5 minutes, so there's no reason
            // for us to freshen the cache more often than that.
            params[gadgets.io.RequestParameters.REFRESH_INTERVAL] = 5 * 60;
            gadgets.io.makeRequest(
                this.url(action),
                function (response) {
                    if (response.errors.length) {
                        // assume if we get an error that it's not permanent.
                        // we'll try hitting the server again if the view is
                        // to be reloaded.
                        self.tabs[action].data = false;
                        self.showMessage(loc('error.fetching-data'));
                    }
                    else {
                        self.tabs[action].data = response.data;
                        self.showData( action );
                    }
                },
                params
            );
        }
    },

    url: function(action) {
        var period = this.prefs.getString('period');
        var workspace = this.prefs.getString('workspace');
        var account = this.prefs.getString('account');
        var url = this.base_uri + '/data/report/' + this.report + '/now/'
                + period + '?action=' + action;
        if (workspace && workspace != 'all') {
            url += '&workspace=' + workspace;
        }
        else if (account) {
            url += '&account=' + account;
        }
        return url;
    },

    showData: function(action) {
        var self = this;
        var data = self.tabs[action].data;

        var maxCount = 0;
        $.each(data.rows, function(i, row) {
            if (Number(row.count) > maxCount) maxCount = Number(row.count);
            // Strip out scheme/domain parts since the same page may be
            // accessed under a different hostname in the past: {bz: 5152}
            if (row.uri) { row.uri = row.uri.replace(/^\w+:\/\/[^/]+/, ''); }
            if (row.context_uri) { row.context_uri = row.context_uri.replace(/^\w+:\/\/[^/]+/, ''); }
        });

        var period_key = 'widgets.' + self.prefs.getString('period').replace(/^-/, '');

        self.render({
            rows: $.grep(data.rows, function(row) { return(row.count > 0); }),
            needsContext: !data.meta[self.context],
            maxCount: maxCount,
            action: action,
            period: loc(period_key),
            context: self.context,
            rotating: self.rotating,
            tabs: self.tabs
        });
        self.fixWidths();
        
        $.each(self.tabs, function(key, tab) {
            $('.tabs .' + key, self.node).click(function() {
                self.showTab(key);
                return false;
            })
        });

        self.window.adjustHeight();
    },

    // {bz: 3044}:
    fixWidths: function() {
        if ($(document.body).hasClass('starfish')) return;

        var self = this;
        try {
            $('div.asset', self.node).each(function() {
                var $widget = $(this).parents('.widget');
                $(this).parents('td.asset').width($widget.width() - 150);
                $(this).width($widget.width() - 150);
            });
        } catch (e) {}
    },

    showTab: function(id) {
        this.stopTimer();
        this.action = id;
        this.prefs.set('view', id);
        this.fetchData();
    },

    nextAction: function() {
        var current_action = this.action || this.default_tab;
        var tabList = [];
        var curtab;
        $.each(this.tabs, function(action) {
            if (action == current_action) {
                curtab = tabList.length; // Record the current selected tab
            }
            tabList.push(action);
        });

        if (curtab+1 >= tabList.length) {
            return tabList[0];
        }
        else {
            return tabList[curtab+1]
        }
    },

    timerName: function() {
        return this.module_id + '-timer';
    },

    stopTimer: function() {
        this.rotating = false;
        $('body').stopTime(this.timerName());
    },

    // this will go on infinitely unless the user clicks on one of the
    // tabs, at which point, it will stop until the page is refreshed.
    // See freshenTabs().
    startTimer: function() {
        var self = this;
        this.rotating = true;
        $('body').everyTime('15s', this.timerName(), function() {
            self.action = self.nextAction();
            if ($('body').is(':visible')) {
                self.fetchData();
            }
        });
    }
};

})(jQuery);
