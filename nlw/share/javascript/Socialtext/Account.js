(function($){

Socialtext = Socialtext || {};
Socialtext.Account = function(params) {
    $.extend(this, params);
};

Socialtext.Account.prototype = new Socialtext.Base();

$.extend(Socialtext.Account.prototype, {
    url: function(rest) {
        if (!this.account_name && this.account_name)
            throw new Error(loc("api.account-name-required"));
        if (!rest) rest = '';
        return '/data/accounts/' + (this.account_id || this.account_name) + rest;
    },

    addUser: function(user, callback) {
        var self = this;
        if (!user.user_id) throw new Error(loc("api.user_id-required"));
        $.ajax({
            url: this.url('/users'),
            type: 'post',
            contentType: 'application/json',
            data: $.toJSON({ user_id: user.user_id }),
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    addGroup: function(group, callback) {
        var self = this;
        if (!group.group_id) throw new Error(loc("api.group_id-required"));
        $.ajax({
            url: this.url('/groups'),
            type: 'post',
            contentType: 'application/json',
            data: $.toJSON({ group_id: group.group_id }),
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    removeGroup: function(group, callback) {
        var self = this;
        if (!group.group_id) throw new Error(loc("api.group_id-required"));
        $.ajax({
            url: this.url('/groups/' + group.group_id),
            type: 'delete',
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    updateSignalsPrefs: function(prefs, callback) {
        var self = this;
        self.updatePluginPrefs('signals', prefs, callback);
    },

    // Generic
    updatePluginPrefs: function(plugin, prefs, callback) {
        var self = this;
        $.ajax({
            url: this.url('/plugins/' + plugin + '/preferences'),
            type: 'put',
            contentType: 'application/json',
            data: $.toJSON(prefs),
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    updateMember: function(member, callback) {
        var self = this;
        $.ajax({
            url: this.url('/users'),
            type: 'POST',
            contentType: 'application/json',
            data: $.toJSON(member),
            success: function() { self._call(callback) },
            error: self.errorCallback(callback)
        });
    },

    _call: function(callback, opts) {
        if (typeof(opts) == 'undefined') opts = {};
        if ($.isFunction(callback)) callback(opts);
    }
});

})(jQuery);
