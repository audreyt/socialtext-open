(function($){

Test.Socialtext = function(params) { };

Test.Socialtext.prototype = new Test.Visual();

$.extend(Test.Socialtext.prototype, {
    groupids: {},
    startTime: (new Date).getTime(),

    createThing: function(url, thing, callback) {
        var self = this;
        $.ajax({
            url: url,
            type: 'POST',
            contentType: 'application/json',
            data: $.toJSON(thing),
            success: callback,
            error: function() {
                self.fail("Workspace doesn't exist!");
                self.endAsync();
            }
        });
    },

    createThings: function(url, things, callback) {
        var self = this;
        var copy = $.extend(true, [], things);
        function nextThing() {
            var thing = copy.shift();
            if (thing) {
                self.createThing(url, thing, function(data) {
                    try { 
                        data = $.evalJSON(data);
                        if (data.group_id)
                            self.groupids[data.name] = data.group_id;
                    }
                    catch (e) {}
                    nextThing();
                });
            }
            else {
                callback();
            }
        }
        nextThing();
    },

    createUsers: function(users, callback) {
        this.createThings('/data/users', users, callback);
    },
 
    createGroups: function(groups, callback) {
        var self = this;
        this.createThings('/data/groups', groups, function() {
            $.each(groups, function(i, group) {
                group.group_id = self.groupids[group.name];
            });
            callback();
        });
    }
});

})(jQuery);
