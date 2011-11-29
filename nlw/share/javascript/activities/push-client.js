(function($) {

var Instances = [];

PushClient = function (opts) {
    $.extend(this,opts);
    this._polling_id = 0;

    if (this.instance_id) {
        if (Instances[this.instance_id]) {
            Instances[this.instance_id].stop();
        }
        Instances[this.instance_id] = this;
    }
};

PushClient.prototype = {
    base_uri: '',
    
    // Hash lookup for seen signals
    _seenSignals: {},

    backoff_timeout: 5000,
    poll_timeout: 600000 * 1.10, // 10 minutes, with 10% wiggle-room
    offline_timeout: 30000, // timeout for retrying after being logged off

    reconnect_backoff: 0, // variable
    reconnect_backoff_increment: 500, // setting
    reconnect_backoff_max: 60000, // setting

    /* For short poll, use:
     *
     * timeout: 3000,
     * nowait: 1,
     */
    timeout: 0,
    nowait: 0,

    start: function() {
        this._polling_id++;
        this._polling = true;
        this._poll();
    },

    stop: function() {
        this._polling = false;
    },

    isPolling: function() {
        return this._polling;
    },

    log: function(msg) {
        if ($.isFunction(this.onLog)) this.onLog(msg);
    },

    reconnectAfter: function(timeout) {
        var self = this;
        if (!timeout) {
            timeout = this.reconnect_backoff;
            if (this.reconnect_backoff < this.reconnect_backoff_max)
                this.reconnect_backoff += this.reconnect_backoff_increment;
        }
        var polling_id = self._polling_id;
        setTimeout(function() {
            if (!self._polling) {
                self.log('Stopped polling');
            }
            else if (self._polling_id != polling_id) {
                self.log('Detected new push client! Exiting');
            }
            else {
                self._poll();
            }
        }, timeout || 1);
    },

    _poll: function() {
        var self = this;

        var success = false;

        var data = {};
        if (self.nowait || !self.client_id) data.nowait = 1;
        if (self.client_id) {
            data.client_id = self.client_id;
            data.sequence = self.sequence;
        }
        else {
            self.sequence = 0;
        }

        var polling_id = self._polling_id;

        $.ajax({
            async: true,
            timeout: self.poll_timeout,
            dataType: 'json',
            url: self.base_uri + '/data/push',
            data: data,
            success: function(data) {
                if (self._polling_id == polling_id) {
                    success = true;
                    self.reconnect_backoff = 0;
                    self.onSuccess(data);
                }
                else {
                    self.log('Detected new push client! Exiting');
                }
            },
            complete: function(xhr) {
                if (!success) {
                    if (self._polling_id == polling_id) {
                        self.onComplete(xhr);
                    }
                    else {
                        self.log('Detected new push client! Exiting');
                    }
                }
            }
        });
    },

    onSuccess: function(data) {
        var self = this;

        var newSignals = [];
        var hiddenSignals = [];
        var likeSignals = [];
        var unlikeSignals = [];
        var newSequence;
        var reconnectTimeout = self.timeout;

        $.each((data || []), function(i,item) {
            var obj = item['object'];
            var cls = item['class'];
            self.sequence++;

            switch (cls) {
                case 'command':
                    self.sequence--;
                    switch (obj.command) {
                        case 'welcome':
                            if (obj.client_id) {
                                self.client_id = obj.client_id;
                                self.log('Got Client ID:' + self.client_id);
                            }
                            if (obj.reconnect_timeout) {
                                if (self.timeout >= obj.reconnect_timeout) {
                                    throw new Error("timeout is set too low!");
                                }
                                self.log('Got timeout:' + reconnectTimeout);
                            }
                            break;
                        case 'goodbye':
                            if (obj.reconnect_after) {
                                reconnectTimeout = obj.reconnect_after;
                            }
                            self.log('Server going away for ' + reconnectTimeout);
                            break;
                        case 'continue':
                            if (typeof(obj.sequence) != 'undefined') {
                                newSequence = obj.sequence;
                            }
                            self.log('Got a continue, seq='+newSequence);
                            break;
                        case 'userlist':
                        case 'status_change':
                            self.updateUserList(obj);
                            break;
                        default:
                            self.log('Unknown command:' + obj.command);
                    };
                    break;
                case 'signal':
                    self.log('Got a Signal: ' + obj.signal_id);
                    if (!self._seenSignals[obj.signal_id]) newSignals.push(obj);
                    self._seenSignals[obj.signal_id] = true;
                    break;
                case 'hide_signal':
                    self.log('Got a Hide-Signal');
                    hiddenSignals.push(obj);
                    break;
                case 'like_signal':
                    self.log('Got a Like-Signal');
                    likeSignals.push(obj);
                    break;
                case 'unlike_signal':
                    self.log('Got a Like-Signal');
                    unlikeSignals.push(obj);
                    break;
                default:
                    self.log('Unknown class: '+cls);
            }
        });

        if (hiddenSignals.length && $.isFunction(self.onHideSignals)) {
            self.onHideSignals(hiddenSignals)
        }

        if (newSignals.length && $.isFunction(self.onNewSignals)) {
            self.onNewSignals(newSignals)
        }

        if (likeSignals.length && $.isFunction(self.onLikeSignals)) {
            self.onLikeSignals(likeSignals)
        }

        if (unlikeSignals.length && $.isFunction(self.onUnlikeSignals)) {
            self.onUnlikeSignals(unlikeSignals)
        }

        if (newSequence != self.sequence) {
            self.log(
                'Sequence mismatch! Resynch required: ' +
                newSequence + ' vs ' + self.sequence
            );
            if ($.isFunction(self.onRefresh)) {
                var polling_id = self._polling_id;
                self.onRefresh();
                if (polling_id != self._polling_id) {
                    self.log('Detected new push client! Exiting');
                    return;
                }
            }
        }

        self.reconnectAfter(reconnectTimeout);
    },

    seenSignal: function(id) {
        this._seenSignals[id] = true;
    },

    updateUserList: function(obj) {
        switch (obj.command) {
            case 'userlist':
                this.userlist = obj.userlist;
            case 'status_change':
                switch (obj.status) {
                    case 'online':
                        this.userlist = $.grep(this.userlist, function(u) {
                            obj.user_id != u
                        });
                        this.userlist.push(obj.user_id);
                        break;
                    case 'offline':
                        this.userlist = $.grep(this.userlist, function(u) {
                            obj.user_id != u
                        });
                        break;
                }
        }
        if ($.isFunction(this.onUserListChange))
            this.onUserListChange(this.userlist);
    },

    onComplete: function(xhr) {
        try {
            var code = (xhr && xhr.status) ? xhr.status : 500;
            this.log("Server explicitly failed with HTTP Code: " + code);
            switch(code) {
                case 400: {
                    this.log('Server forgot us.');
                    this._reset();
                    this._restart();
                    if ($.isFunction(this.onRefresh)) {
                        var polling_id = self._polling_id;
                        this.onRefresh();
                        if (polling_id != this._polling_id) {
                            this.log('Detected new push client! Exiting');
                            return;
                        }
                    }
                    break;
                }
                case 403: {
                    this.log('Forbidden: probably offline');
                    this._restart(this.offline_timeout);
                    if ($.isFunction(this.onError)) this.onError();
                    break;
                }
                case 502: case 503: {
                    this.log('Server temporarily unavailable.');
                    this._restart(this.backoff_timeout);
                    break;
                }
                default: {
                    this.log('Push daemon went away');
                    if ($.isFunction(this.onError)) this.onError();
                    this._restart(this.backoff_timeout);
                }
            }
        }
        catch(e) {
            if (this.client_id && e.code && e.code == 11) {
                this.log('Timeout');
                this._restart();
            }
            else {
                this.log('Server unavailable for unknown reasons.');
                this._restart(this.backoff_timeout);
            }
        }
    },

    _reset: function() {
        this.client_id = null;
        this.sequence = null;
    },

    _restart: function(timeout) {
        this.log(
            timeout ? 'Restarting signals in ' + timeout + 'ms'
                    : 'Restarting signals now'
        );
        this.reconnectAfter(timeout);
    }
};

})(jQuery);
