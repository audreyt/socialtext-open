(function($){

Socialtext = Socialtext || {};

Socialtext.User = function(params) {
    $.extend(this, params);
};

Socialtext.User.prototype = new Socialtext.Base();

$.extend(Socialtext.User.prototype, {
    create: function() {
        throw new Error(loc("api.unimplemented"));
    },

    url: function() {
        if (!this.user_id) throw new Error(loc("api.no-user-id"));
        return '/data/users/' + this.user_id;
    },

    setPrimaryAccountId: function(id, callback) {
        var self = this;
        if (!callback) callback = function(r) { if (r.error) alert(r.error) };
        if (!id) throw new Error(loc("api.id-required"));
        $.ajax({
            url: this.url(),
            type: 'put',
            contentType: 'application/json',
            data: $.toJSON({
                primary_account_id: id
            }),
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    addToGroups: function(groups, callback) {
        var self = this;
        var jobs = [];
        if (!groups.length) return this.call(callback);
        var errors = [];
        $.each(groups, function(i, info) {
            jobs.push(function(cb) {
                var group = new Socialtext.Group({group_id: info.id});
                group.addMembers(
                    [{user_id: self.user_id, role: 'member'}], cb);
            });
        });
        this.runAsynch(jobs, callback);
    },

    removeFromWorkspaces: function(workspaces, callback) {
        var self = this;
        var jobs = [];
        if (!workspaces.length) return this.call(callback);
        var errors = [];
        $.each(workspaces, function(i, info) {
            jobs.push(function(cb) {
                var workspace = new Socialtext.Workspace({
                    name: info.name
                });
                workspace.removeMembers([ { user_id: self.user_id } ], cb);
            });
        });
        this.runAsynch(jobs, callback);
    }
});

})(jQuery);
