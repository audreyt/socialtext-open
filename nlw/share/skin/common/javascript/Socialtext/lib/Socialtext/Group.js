(function($){

Socialtext = Socialtext || {};
Socialtext.Group = function(params) {
    $.extend(this, params);
};

Socialtext.Group.GetDrivers = function(callback) {
    $.getJSON('/data/group_drivers', callback);
};

Socialtext.Group.GetDriverGroups = function(driver_key, callback) {
    var url = '/data/group_drivers/' + driver_key + '/groups';
    $.getJSON(url, callback);
};

Socialtext.Group.prototype = new Socialtext.Base();

$.extend(Socialtext.Group.prototype, {
    url: function(rest) {
        rest = rest || '';
        return '/data/groups/' + this.group_id + rest;
    },

    load: function(callback) {
        var self = this;
        $.ajax({
            url: self.url(),
            type: 'get',
            dataType: 'json',
            success: function(data) {
                $.extend(self, data);
                callback();
            },
            error: self.errorCallback(callback)
        });
    },

    saveInfo: function(callback) {
        var self = this;
        if (!this.name && !this.ldap_dn) {
            throw new Error(loc("api.ldap-dn-or-group-name-required"));
        }

        var data = {};
        $.each(Socialtext.Group.Args.PUT, function(i, arg) {
            if (self[arg]) data[arg] = self[arg];
        });

        $.ajax({
            url: self.url(),
            type: 'PUT',
            contentType: 'application/json',
            data: $.toJSON(data),
            success: function() {
                if (callback) callback({});
            },
            error: this.errorCallback(callback)
        });
    },

    save: function(callback) {
        var self = this;
        if (!self.group_id) {
            throw new Error("Can't save group without group_id");
        }

        var users = {
            users: self.users,
            send_message: self.send_message,
            additional_message: self.additional_message
        };
        var jobs = [
            function(cb) { self.saveInfo(cb) },
            function(cb) { self.addMembers(users, cb) },
            function(cb) { self.addToWorkspaces(self.workspaces, cb) },
            function(cb) { self.updateMembers(self.changedmemberships, cb) },
            function(cb) { self.removeMembers(self.trash, cb) },
            function(cb) {
                self.removeFromWorkspaces(self.trashed_workspaces, cb)
            }
        ];
        $.each(self.new_workspaces || [], function(i, info) {
            info.groups = {group_id: self.group_id};
            info.permission_set = self.workspace_compat_perms();
            jobs.push(function(cb) {
                Socialtext.Workspace.Create(info, cb);
            });
        });

        self.runAsynch(jobs, function() {
            self._call(callback, self);
        });
    },

    workspace_compat_perms: function() {
        return (this.permission_set == 'self-join')
            ? 'self-join' : 'member-only';
    },

    /**
     * addMembers(userList, options, callback)
     *
     * accepts: 
     *   an array of users [{user_id:...},...], or
     *   a hash {
     *      users: [], // users
     *      send_message: true/false,
     *      additional_message: "invite message"
     *   }
     */
    addMembers: function(users, callback) {
        // If an array, then make it into a structure
        if ((Object.prototype.toString.call(users) === '[object Array]') ||   !users) { 
            users = {users: (users || [])};
        };
        if (!users.users.length) return callback({});
        this.postItems(this.url('/users'), users, callback);
    },

    _call: function(callback, opts) {
        if (typeof(opts) == 'undefined') opts = {};
        if ($.isFunction(callback)) callback(opts);
    },

    updateMembers: function(members, callback) {
        if (!members.length) return this._call(callback);
        this.postItems(this.url('/membership'), members, callback);
    },

    addToWorkspaces: function(workspaces, callback) {
        if (!workspaces.length) return this._call(callback);
        this.postItems(this.url('/workspaces'), workspaces, callback);
    },

    removeFromWorkspaces: function(workspaces, callback) {
        var self = this;
        var jobs = [];
        if (!workspaces.length) return this._call(callback);
        $.each(workspaces, function(i, info) {
            jobs.push(function(cb) {
                var workspace = new Socialtext.Workspace({
                    name: info.name
                });
                workspace.removeMembers(
                    [ { group_id: self.group_id } ], cb
                );
            });
        });
        this.runAsynch(jobs, callback);
    },

    removeFromAccounts: function(accounts, callback) {
        var self = this;
        var jobs = [];
        if (!accounts.length) return this._call(callback);
        $.each(accounts, function(i, info) {
            jobs.push(function(cb) {
                var account = new Socialtext.Account({
                    account_name: info.name
                });
                account.removeGroup(self, cb);
            });
        });
        this.runAsynch(jobs, callback);
    },

    removeMembers: function(trash, callback) {
        if (!trash.length) return this._call(callback);
        this.postItems(this.url('/trash'), trash, callback);
    },

    postItems: function(url, list, callback) {
        var self = this;
        $.ajax({
            url: url,
            type: 'POST',
            contentType: 'application/json',
            data: $.toJSON(list),
            success: function() { self._call(callback) },
            error: self.errorCallback(callback)
        });
    },

    hasMember: function(username, callback) {
        var self = this;
        if (!Number(self.group_id)) {
            self._call(callback, false);
        }
        else {
            $.ajax({
                url: this.url('/users/' + username),
                type: 'HEAD',
                success: function() { self._call(callback, true) },
                error:   function() { self._call(callback, false) }
            });
        }
    },

    getAdmins: function(callback) {
        $.getJSON(this.url('?show_admins=1'), function(data) { 
            var result=[];
            result = $.map(data.admins, function(elem, index) {
                return elem.user_id;
            });
            callback(result);
        });
    },

    remove: function(callback) {
        $.ajax({
            url: this.url(),
            type: 'DELETE',
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    }
});

Socialtext.Group.Args = {
    POST: [
        'ldap_dn', 'name', 'account_id', 'description', 'photo_id',
        'workspaces', 'users', 'send_message', 'additional_message',
        'new_workspaces', 'permission_set'
    ],
    PUT: [ 'name', 'account_id', 'description', 'photo_id', 'permission_set' ]
};

Socialtext.Group.Create = function(opts, callback) {
    if (!opts.name && !opts.ldap_dn) {
        throw new Error(loc("api.ldap-dn-or-group-name-required"));
    }

    var data = {};
    $.each(Socialtext.Group.Args.POST, function(i, arg) {
        if (opts[arg]) data[arg] = opts[arg]
    });

    $.ajax({
        url: '/data/groups',
        type: 'POST',
        dataType: 'json',
        contentType: 'application/json',
        data: $.toJSON(data),
        success: function(data) {
            var group = new Socialtext.Group(data);
            if (callback) callback(group);
        },
        error: function(xhr, textStatus, errorThrown) {
            var error = xhr ? xhr.responseText : errorThrown;
            if (callback) callback({ errors: [error] });
        }
    });
};

})(jQuery);
