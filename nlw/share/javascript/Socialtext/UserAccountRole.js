(function($){

Socialtext = Socialtext || {};

Socialtext.UserAccountRole = function(params) {
    $.extend(this, params);
};

Socialtext.UserAccountRole.prototype = new Socialtext.Base();

$.extend(Socialtext.UserAccountRole.prototype, {
    url: function() {
        if (!this.username) throw new Error(loc("api.username-required"));
        if (!this.account_name)
            throw new Error(loc("api.account_name-required"));

        return '/data/accounts/' + this.account_name +
               '/users/' + this.username;
    },

    remove: function(callback) {
        if (!callback) callback = function(r) { if (r.error) alert(r.error) };
        $.ajax({
            url: this.url(),
            type: 'delete',
            success: this.successCallback(callback),
            error: this.errorCallback(callback)
        });
    },

    stringify: function() {
        var roles = [];
        if (this.is_primary != undefined) {
            if (this.is_primary) {
                roles.push(loc("api.primary-account"));
            }
            else {
                roles.push(loc("api.member-of-account"));
            }
        }
        if (this.via_workspace) {
            roles.push(loc(
                "api.via-wiki-count=length,map",
                this.via_workspace.length,
                $.map(this.via_workspace, function (w) {
                    var href = "/nlw/control/workspace/" + w.workspace_id;
                    return '<a href="' + href + '">' + w.name + '</a>';
                }).join(", ")
            ));
        }
        if (this.via_group) {
            roles.push(loc(
                "api.via-group-count=length,map",
                this.via_group.length,
                $.map(this.via_group, function (g) {
                    var href = "/nlw/control/group/" + g.group_id;
                    return '<a href="' + href + '">' + g.name + '</a>';
                }).join(", ")
            ));
        }
        return roles.join(', ');
    }
});

})(jQuery);
