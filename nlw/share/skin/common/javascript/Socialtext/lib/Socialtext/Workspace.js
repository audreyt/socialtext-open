(function($) {

Socialtext = Socialtext || {};
Socialtext.Workspace = function(params) {
    delete params.create;
    $.extend(this, params);
};

Socialtext.Workspace.prototype = new Socialtext.Base();

$.extend(Socialtext.Workspace.prototype, {
    url: function(extra) {
        if (!extra) extra = '';
        return '/data/workspaces/' + this.name + extra
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
    _splitMemberRoles: function(members) {
        // XXX: We should make /data/workspace/:ws/members so we don't need to
        // split this here
        var roles = { users: [], groups: [] };
        $.each(members, function(i, mem) {
            var role = {};
            if (mem.role_name) role.role_name = mem.role_name;
            if (mem.group_id) role.group_id = mem.group_id;
            if (mem.user_id) role.user_id = mem.user_id;
            if (mem.username) role.username = mem.username;
            if (mem.group_id) {
                roles.groups.push(role);
            }
            else if (mem.user_id || mem.username) {
                roles.users.push(role);
            }
        });
        return roles;
    },
    _hasImpersonators: function(members) {
        var self = this;

        var hasImpersonators = false;
        $(members).each(function(i, member) {
            if (member.roles && $.inArray('impersonator', member.roles) != -1) {
                hasImpersonators = true;
            }
        });

        return hasImpersonators;
    },
    _request: function(method, collection, data, callback) {
        var self = this;
        $.ajax({
            url: self.url('/' + collection),
            type: method,
            contentType: 'application/json',
            data: $.toJSON(data),
            success: self.successCallback(callback),
            error: self.errorCallback(callback)
        });
    },
    updateMembers: function(members, callback) {
        var self = this;
        if (self._hasImpersonators(members)) {
            callback({errors: [loc('api.impersonators-can-only-be-managed-by-admins')]});
        }
        else {
            var types = self._splitMemberRoles(members);
            if (!types.users.length && !types.groups.length) {
                throw new Error(loc("api.no-members-specified"));
            }
            var jobs = [];
            if (types.users.length) {
                jobs.push(function(cb) {
                    self._request('PUT', 'users', types.users, cb)
                });
            }
            if (types.groups.length) {
                jobs.push(function(cb) {
                    self._request('PUT', 'groups', types.groups, cb)
                });
            }
            self.runAsynch(jobs, callback);
        }
    },
    addMembers: function(members, callback) {
        var self = this;
        var jobs = [];
        $.each(members, function(i, member) {
            if (member.group_id) {
                jobs.push(function(cb) {
                    self._request('POST', 'groups', member, cb)
                });
            }
            else {
                jobs.push(function(cb) {
                    self._request('POST', 'users', member, cb)
                });
            }
        });
        this.runAsynch(jobs, callback);
    },
    removeMembers: function(members, callback) {
        var self = this;

        if (self._hasImpersonators(members)) {
            callback({errors: ['Impersonators can only be managed by system administrators']});
        }
        else {
            var data = $.map(members, function(member) {
                var r = {};
                if (member.user_id) r.user_id = member.user_id;
                if (member.group_id) r.group_id = member.group_id;
                if (member.username) r.username = member.username;
                return r;
            });
            $.ajax({
                url: this.url('/trash'),
                type: 'POST',
                contentType: 'application/json',
                data: $.toJSON(data),
                success: this.successCallback(callback),
                error: this.errorCallback(callback)
            });
        }
    }
});

/**
 * Class Methods
 */
Socialtext.Workspace.All = function(callback) {
    $.ajax({
        url: '/data/workspaces',
        type: 'get',
        dataType: 'json',
        success: function(data) {
            var workspaces = [];
            $.each(data, function(i, w) {
                workspaces.push( new Socialtext.Workspace(w) );
            });
            callback({ data: workspaces });
        },
        error: function(xhr, textStatus, errorThrown) {
            var error = xhr ? xhr.responseText : errorThrown;
            callback({ error: error });
        }
    });
};

Socialtext.Workspace.Create = function(opts, callback) {
    try {
        if (!opts.title) throw new Error(loc("api.title-required"));
        if (!opts.name) throw new Error(loc("api.name-required"));
        Socialtext.Workspace.AssertValidTitle(opts.title);
        Socialtext.Workspace.AssertValidName(opts.name);
    }
    catch(e) {
        callback({error: e.message});
        return;
    }

    var data = {};
    if (opts.title) data.title = opts.title;
    if (opts.name) data.name = opts.name;
    if (opts.groups) data.groups = opts.groups;
    if (opts.account_id) data.account_id = opts.account_id;
    if (opts.members) data.members = opts.members;
    if (opts.permission_set) data.permission_set = opts.permission_set;

    opts.accept = 'application/json';

    $.ajax({
        url: '/data/workspaces',
        type: 'POST',
        contentType: 'application/json',
        data: $.toJSON(data),
        success: function(data) {
            var workspace = new Socialtext.Workspace({name: opts.name});
            if (callback) callback(workspace);
        },
        error: function(xhr, textStatus, errorThrown) {
            var error = xhr ? xhr.responseText : errorThrown;
            if (callback) callback({ error: error || textStatus });
        }
    });
}

Socialtext.Workspace.ReservedNames = [
    'account', 'administrate', 'administrator', 'atom', 'attachment',
    'attachments', 'category', 'control', 'console', 'data', 'feed', 'nlw',
    'noauth', 'page', 'recent-changes', 'rss', 'search', 'soap', 'static',
    'st-archive', 'superuser', 'test-selenium', 'workspace', 'user'
];

Socialtext.Workspace.AssertValidTitle = function (title) {
    if (title.match(/^-/)) {
        throw new Error(loc('api.wiki-title-cannot-begin-with-dash'));
    }
    if (title.length < 2 || title.length > 64) {
        throw new Error(loc("api.about-wiki-title"));
    }
};

Socialtext.Workspace.AssertValidName = function (name) {
    var reserved = Socialtext.Workspace.ReservedNames;
    if ($.inArray(name, reserved) >= 0 || name.match(/^st_/)) {
        throw new Error(loc("api.is-reserved-word=name", name));
    }
    if (name.match(/^-/)) {
        throw new Error(loc('api.wiki-name-cannot-begin-with-dash'));
    }
    if (!name.match(/^[a-z0-9_-]{3,30}$/)) {
        throw new Error(
            loc('api.about-wiki-name')
        );
    }
};


/* DO NOT EDIT THIS FUNCTION! run dev-bin/generate-title-to-id-js.pl --dash instead */
/* DO NOTE THAT FOR WORKSPACES WE USE DASH (-) INSTEAD OF UNDERSCORE (_) */
Socialtext.Workspace.page_title_to_page_id = function (str) {
    str = str.replace(/^\s+/, '').replace(/\s+$/, '').replace(/[\u0000-\u002F\u003A-\u0040\u005B-\u005E\u0060\u007B-\u00A9\u00AB-\u00B1\u00B4\u00B6-\u00B8\u00BB\u00BF\u00D7\u00F7\u02C2-\u02C5\u02D2-\u02DF\u02E5-\u02EB\u02ED\u02EF-\u02FF\u0375\u0378-\u0379\u037E-\u0385\u0387\u038B\u038D\u03A2\u03F6\u0482\u0526-\u0530\u0557-\u0558\u055A-\u0560\u0588-\u0590\u05BE\u05C0\u05C3\u05C6\u05C8-\u05CF\u05EB-\u05EF\u05F3-\u060F\u061B-\u0620\u065F\u066A-\u066D\u06D4\u06DD\u06E9\u06FD-\u06FE\u0700-\u070F\u074B-\u074C\u07B2-\u07BF\u07F6-\u07F9\u07FB-\u07FF\u082E-\u08FF\u093A-\u093B\u094F\u0956-\u0957\u0964-\u0965\u0970\u0973-\u0978\u0980\u0984\u098D-\u098E\u0991-\u0992\u09A9\u09B1\u09B3-\u09B5\u09BA-\u09BB\u09C5-\u09C6\u09C9-\u09CA\u09CF-\u09D6\u09D8-\u09DB\u09DE\u09E4-\u09E5\u09F2-\u09F3\u09FA-\u0A00\u0A04\u0A0B-\u0A0E\u0A11-\u0A12\u0A29\u0A31\u0A34\u0A37\u0A3A-\u0A3B\u0A3D\u0A43-\u0A46\u0A49-\u0A4A\u0A4E-\u0A50\u0A52-\u0A58\u0A5D\u0A5F-\u0A65\u0A76-\u0A80\u0A84\u0A8E\u0A92\u0AA9\u0AB1\u0AB4\u0ABA-\u0ABB\u0AC6\u0ACA\u0ACE-\u0ACF\u0AD1-\u0ADF\u0AE4-\u0AE5\u0AF0-\u0B00\u0B04\u0B0D-\u0B0E\u0B11-\u0B12\u0B29\u0B31\u0B34\u0B3A-\u0B3B\u0B45-\u0B46\u0B49-\u0B4A\u0B4E-\u0B55\u0B58-\u0B5B\u0B5E\u0B64-\u0B65\u0B70\u0B72-\u0B81\u0B84\u0B8B-\u0B8D\u0B91\u0B96-\u0B98\u0B9B\u0B9D\u0BA0-\u0BA2\u0BA5-\u0BA7\u0BAB-\u0BAD\u0BBA-\u0BBD\u0BC3-\u0BC5\u0BC9\u0BCE-\u0BCF\u0BD1-\u0BD6\u0BD8-\u0BE5\u0BF3-\u0C00\u0C04\u0C0D\u0C11\u0C29\u0C34\u0C3A-\u0C3C\u0C45\u0C49\u0C4E-\u0C54\u0C57\u0C5A-\u0C5F\u0C64-\u0C65\u0C70-\u0C77\u0C7F-\u0C81\u0C84\u0C8D\u0C91\u0CA9\u0CB4\u0CBA-\u0CBB\u0CC5\u0CC9\u0CCE-\u0CD4\u0CD7-\u0CDD\u0CDF\u0CE4-\u0CE5\u0CF0-\u0D01\u0D04\u0D0D\u0D11\u0D29\u0D3A-\u0D3C\u0D45\u0D49\u0D4E-\u0D56\u0D58-\u0D5F\u0D64-\u0D65\u0D76-\u0D79\u0D80-\u0D81\u0D84\u0D97-\u0D99\u0DB2\u0DBC\u0DBE-\u0DBF\u0DC7-\u0DC9\u0DCB-\u0DCE\u0DD5\u0DD7\u0DE0-\u0DF1\u0DF4-\u0E00\u0E3B-\u0E3F\u0E4F\u0E5A-\u0E80\u0E83\u0E85-\u0E86\u0E89\u0E8B-\u0E8C\u0E8E-\u0E93\u0E98\u0EA0\u0EA4\u0EA6\u0EA8-\u0EA9\u0EAC\u0EBA\u0EBE-\u0EBF\u0EC5\u0EC7\u0ECE-\u0ECF\u0EDA-\u0EDB\u0EDE-\u0EFF\u0F01-\u0F17\u0F1A-\u0F1F\u0F34\u0F36\u0F38\u0F3A-\u0F3D\u0F48\u0F6D-\u0F70\u0F85\u0F8C-\u0F8F\u0F98\u0FBD-\u0FC5\u0FC7-\u0FFF\u104A-\u104F\u109E-\u109F\u10C6-\u10CF\u10FB\u10FD-\u10FF\u1249\u124E-\u124F\u1257\u1259\u125E-\u125F\u1289\u128E-\u128F\u12B1\u12B6-\u12B7\u12BF\u12C1\u12C6-\u12C7\u12D7\u1311\u1316-\u1317\u135B-\u135E\u1360-\u1368\u137D-\u137F\u1390-\u139F\u13F5-\u1400\u166D-\u166E\u1680\u169B-\u169F\u16EB-\u16ED\u16F1-\u16FF\u170D\u1715-\u171F\u1735-\u173F\u1754-\u175F\u176D\u1771\u1774-\u177F\u17B4-\u17B5\u17D4-\u17D6\u17D8-\u17DB\u17DE-\u17DF\u17EA-\u17EF\u17FA-\u180A\u180E-\u180F\u181A-\u181F\u1878-\u187F\u18AB-\u18AF\u18F6-\u18FF\u191D-\u191F\u192C-\u192F\u193C-\u1945\u196E-\u196F\u1975-\u197F\u19AC-\u19AF\u19CA-\u19CF\u19DB-\u19FF\u1A1C-\u1A1F\u1A5F\u1A7D-\u1A7E\u1A8A-\u1A8F\u1A9A-\u1AA6\u1AA8-\u1AFF\u1B4C-\u1B4F\u1B5A-\u1B6A\u1B74-\u1B7F\u1BAB-\u1BAD\u1BBA-\u1BFF\u1C38-\u1C3F\u1C4A-\u1C4C\u1C7E-\u1CCF\u1CD3\u1CF3-\u1CFF\u1DE7-\u1DFC\u1F16-\u1F17\u1F1E-\u1F1F\u1F46-\u1F47\u1F4E-\u1F4F\u1F58\u1F5A\u1F5C\u1F5E\u1F7E-\u1F7F\u1FB5\u1FBD\u1FBF-\u1FC1\u1FC5\u1FCD-\u1FCF\u1FD4-\u1FD5\u1FDC-\u1FDF\u1FED-\u1FF1\u1FF5\u1FFD-\u203E\u2041-\u2053\u2055-\u206F\u2072-\u2073\u207A-\u207E\u208A-\u208F\u2095-\u20CF\u20F1-\u2101\u2103-\u2106\u2108-\u2109\u2114\u2116-\u2118\u211E-\u2123\u2125\u2127\u2129\u212E\u213A-\u213B\u2140-\u2144\u214A-\u214D\u214F\u218A-\u245F\u249C-\u24E9\u2500-\u2775\u2794-\u2BFF\u2C2F\u2C5F\u2CE5-\u2CEA\u2CF2-\u2CFC\u2CFE-\u2CFF\u2D26-\u2D2F\u2D66-\u2D6E\u2D70-\u2D7F\u2D97-\u2D9F\u2DA7\u2DAF\u2DB7\u2DBF\u2DC7\u2DCF\u2DD7\u2DDF\u2E00-\u2E2E\u2E30-\u3004\u3008-\u3020\u3030\u3036-\u3037\u303D-\u3040\u3097-\u3098\u309B-\u309C\u30A0\u30FB\u3100-\u3104\u312E-\u3130\u318F-\u3191\u3196-\u319F\u31B8-\u31EF\u3200-\u321F\u322A-\u3250\u3260-\u327F\u328A-\u32B0\u32C0-\u33FF\u4DB6-\u4DFF\u9FCC-\u9FFF\uA48D-\uA4CF\uA4FE-\uA4FF\uA60D-\uA60F\uA62C-\uA63F\uA660-\uA661\uA673-\uA67B\uA67E\uA698-\uA69F\uA6F2-\uA716\uA720-\uA721\uA789-\uA78A\uA78D-\uA7FA\uA828-\uA82F\uA836-\uA83F\uA874-\uA87F\uA8C5-\uA8CF\uA8DA-\uA8DF\uA8F8-\uA8FA\uA8FC-\uA8FF\uA92E-\uA92F\uA954-\uA95F\uA97D-\uA97F\uA9C1-\uA9CE\uA9DA-\uA9FF\uAA37-\uAA3F\uAA4E-\uAA4F\uAA5A-\uAA5F\uAA77-\uAA79\uAA7C-\uAA7F\uAAC3-\uAADA\uAADE-\uABBF\uABEB\uABEE-\uABEF\uABFA-\uABFF\uD7A4-\uD7AF\uD7C7-\uD7CA\uD7FC-\uF8FF\uFA2E-\uFA2F\uFA6E-\uFA6F\uFADA-\uFAFF\uFB07-\uFB12\uFB18-\uFB1C\uFB29\uFB37\uFB3D\uFB3F\uFB42\uFB45\uFBB2-\uFBD2\uFD3E-\uFD4F\uFD90-\uFD91\uFDC8-\uFDEF\uFDFC-\uFDFF\uFE10-\uFE1F\uFE27-\uFE32\uFE35-\uFE4C\uFE50-\uFE6F\uFE75\uFEFD-\uFF0F\uFF1A-\uFF20\uFF3B-\uFF3E\uFF40\uFF5B-\uFF65\uFFBF-\uFFC1\uFFC8-\uFFC9\uFFD0-\uFFD1\uFFD8-\uFFD9\uFFDD-\uFFFF]+/g,'-');
    str = str.replace(/-+/g, '-');
    str = str.replace(/(^-|-$)/g, '');
    if (str == '0') str = '-';
    if (str == '') str = '-';
    return str.toLocaleLowerCase();
} /* function page_title_to_page_id */

Socialtext.Workspace.TitleToName = function (title) {
    if (title == '')
        return '';
    return encodeURI(this.page_title_to_page_id(title));
};

Socialtext.Workspace.CheckExists = function (name, callback) {
    $.ajax({
        url: '/data/workspaces/' + name,
        type: 'get',
        dataType: 'json',
        complete: function(xhr) {
            if (xhr.status == 200) {
                callback(true);
            }
            else if (xhr.status == 404) {
                callback(false);
            }
            else {
                throw new Error(loc("api.error-checking-for-wiki-existence"));
            }
        }
    });
};

})(jQuery);
