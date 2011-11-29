var t = new Test.Socialtext();

t.plan(26);

var workspaceTitle = "My Workspace " + t.startTime;
var workspaceName = 'my_workspace_' + t.startTime;
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

var testGroups = [
    {
        name: "group1" + t.startTime,
        role_name: 'member'
    },
    {
        name: "group2" + t.startTime,
        role_name: 'member'
    }
];


var workspace;

function usersCorrect (callback) {
    $.ajax({
        url: workspace.url('/users?order=user_id'),
        type: 'GET',
        dataType: 'json',
        success: function(data) {
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

function groupsCorrect (callback) {
    $.ajax({
        url: workspace.url('/groups'),
        type: 'GET',
        dataType: 'json',
        success: function(data) {
            t.is(data[0].name, testGroups[0].name, data[0].name);
            t.is(data[1].name, testGroups[1].name, data[1].name);
            t.is(data[0].role_name, testGroups[0].role_name, data[0].role_name);
            t.is(data[1].role_name, testGroups[1].role_name, data[1].role_name);
            callback();
        },
        error: function() {
            t.fail("Can't get groups");
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
    function() {
        t.createGroups(testGroups, t.nextStep());
    },

    function() {
        $.ajax({
            type: 'GET',
            url: '/data/users/devnull1@socialtext.com',
            dataType: 'json',
            success: function(data) {
                t.__primary_account_id__ = data.primary_account_id;
                t.callNextStep();
            }
        });
    },

    /*
     * Create a Workspace
     */
    function() {
        Socialtext.Workspace.Create({
            title: workspaceTitle,
            name: workspaceName,
            account_id: t.__primary_account_id__
        }, function() {
            t.pass("Created Workspace");
            t.callNextStep();
        });
    },

    /**
     * Make sure the workspace was created properly (title correct, etc)
     */
    function() {
        workspace = new Socialtext.Workspace({ name: workspaceName });

        $.ajax({
            url: workspace.url(),
            type: 'GET',
            dataType: 'json',
            success: function(data) {
                t.is(data.title, workspaceTitle, "Workspace title is correct");
                t.nextStep()();
            },
            error: function() {
                t.fail("Workspace doesn't exist!");
                t.endAsync();
            }
        });
    },

    /**
     * Add some members
     */
    function() {
        workspace.addMembers(testUsers.concat(testGroups), t.nextStep());
    },
    
    /**
     * Make sure the members were created properly
     */
    function() {
        usersCorrect(t.nextStep());
    },
    function() {
        groupsCorrect(t.nextStep());
    },

    function() {
        testUsers[0].role_name = 'admin';
        workspace.updateMembers([ testUsers[0] ], t.nextStep());
    },

    function() {
        usersCorrect(t.nextStep());
    },

    function() {
        groupsCorrect(t.nextStep());
    },

    function() {
        testGroups[1].role_name = 'admin';
        workspace.updateMembers([ testGroups[1] ], t.nextStep());
    },

    function() {
        usersCorrect(t.nextStep());
    },

    function() {
        groupsCorrect(t.nextStep());
    },

    function() {
        t.endAsync();
    }
]);

