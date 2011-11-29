var t = new Test.Socialtext();

t.plan(15);

var groupName = "Shiny Group " + t.startTime;
var testUsers = [
    {
        username: "user1" + t.startTime + "@ken.socialtext.net",
        email_address: "user1" + t.startTime + "@ken.socialtext.net",
        role_name: 'member'
    },
    {
        username: "user2" + t.startTime + "@ken.socialtext.net",
        email_address: "user2" + t.startTime + "@ken.socialtext.net",
        role_name: 'member'
    }
];

var group;

function usersCorrect (callback) {
    $.ajax({
        url: group.url('/users'), // XXX: order=user_id
        type: 'GET',
        dataType: 'json',
        success: function(data) {
            // XXX:
            data[1].username=data[1].name;data[2].username=data[2].name;

            t.is(data.length, 3, "Correct number of members");

            t.is(data[1].username, testUsers[0].username, data[1].username);
            t.is(data[2].username, testUsers[1].username, data[2].username);
            t.is(data[1].role_name, testUsers[0].role_name, data[1].role_name);
            t.is(data[2].role_name, testUsers[1].role_name, data[2].role_name);
            callback();
        },
        error: function() {
            t.fail("Can't get users");
            t.endAsync();
        }
    });
}

t.runAsync([

    /*
     * Create some test users and groups
     */
    function() {
        t.createUsers(testUsers, t.nextStep());
    },

    /*
     * Create a Group
     */
    function() {
        Socialtext.Group.Create({ name: groupName }, function(res) {
            t.ok(!res.errors, "No errors creating group");
            group = res;
            t.ok(group.group_id, "Created Group");
            t.nextStep()();
        });
    },

    /*
     * Can't create a second group with the same name
     */
    function() {
        Socialtext.Group.Create({ name: groupName }, function(res) {
            t.is(res.errors[0], "group already exists\n", "Created Group");
            t.nextStep()();
        });
    },

    /**
     * Add some members
     */
    function() {
        group.addMembers(testUsers, t.nextStep());
    },
    
    /**
     * Make sure the members were created properly
     */
    function() {
        usersCorrect(t.nextStep());
    },
    function() {
        testUsers[0].role_name = 'admin';
        group.updateMembers([ testUsers[0] ], t.nextStep());
    },
    function() {
        usersCorrect(t.nextStep());
    },

    /**
     * Delete a group
     */
    function() {
        group.remove(t.nextStep());
    },
    function(res) {
        t.ok(!res.errors, "No errors removing group");
        $.ajax({
            url: group.url(),
            success: function() {
                t.fail("Group wasn't removed");
                t.nextStep()();
            },
            error: function(xhr) {
                t.is(xhr.status, 404, "404 after deleting group");
                t.nextStep()();
            }
        });
    },

    function() {
        t.endAsync();
    }
]);

