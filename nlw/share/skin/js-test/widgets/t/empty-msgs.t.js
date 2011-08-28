(function($) {

var t = new Test.Visual();
t.skipAll("Test is no longer functional - Workspaces now always have AUWs and profile widgets are inlined; skipAll for now");

var steps = [
    function() { t.login({}, t.nextStep()) }, 
    function() { t.create_anonymous_user_and_login({}, t.nextStep()) }, 
];

var testData = [
    {
        type: "one_widget",
        name: "Workspaces",
        regex: /This person belongs to no workspaces|You do not belong to any workspaces yet/,
        desc: "Empty My Workspaces message is correct"
    },
    {
        type: "open_iframe",
        widget: "Tags",
        url: "/?profile/7",
        regex: /This person has no tags/,
        desc: "Empty message for another user's profile tags is present and correct"
    }
    /*
    {
        type: "one_widget",
        name: "All People Tags",
        regex: /You don't have any tags yet. Click <b>Add tag<\/b> to add one now./,
        desc: "Empty message for profile tags is present and correct"
    },
    */
    /*,
    {
        type: "one_widget",
        url: "/?action=add_widget;type=dashboard;src=file:people/share/profile_following.xml",
        regex: /You are not following anyone yet. When viewing someone else's profile, you can click on the "Follow this person" button at the top of the page./,
        desc: "Empty message for my \"Persons I'm Following\" list."
    },
    {
        type: "open_iframe",
        widget: "people_i_am_following",
        url: "/?profile/7",
        regex: /This person isn't following anyone yet./,
        desc: "Empty message for someone else's \"Persons I'm Following\" list."
    },
    { // Create a new user in the admin workspace...
        type: 'user_with_workspace'
    },
    {
        type: "one_widget",
        url: "/?action=add_widget;type=dashboard;src=file:widgets/share/widgets/recent_conversations.xml",
        regex: /My Conversations shows updates to pages you are involved with. To see entries in my conversation, edit, comment on, or watch a page. When someone else modifies that page, you will see those updates here./,
        desc: "Empty message for my \"Recent Conversations\" list."
    }
    */
];

t.plan(testData.length);

if (jQuery.browser.msie)
    t.skipAll("Skipping this insanity on IE for now");

// Generate the test step functions for each test.
for (var i = 0, l = testData.length; i < l; i++) {
    (function(d) {
        if (d.type == 'user_with_workspace') {
            steps.push(function() {
                t.login({}, function() {
                    t.create_anonymous_user_and_login(
                        {workspace: 'admin'},
                        t.nextStep()
                    );
                });
            });
            return;
        }
        var step1 = (d.type == 'one_widget')
        ? function() {
            t.setup_one_widget(
                d.name,
                t.nextStep()
            );
        }
        : function() {
            t.open_iframe(d.url, function() {
                t.scrollTo(150);
                t.getWidget(d.widget, t.nextStep());
            });
        };
        steps.push(step1);

        var step2 = function(widget) {
            t.scrollTo(150);
            t.like(widget.$("body").html(), d.regex, d.desc);
            t.callNextStep();
        };
        steps.push(step2);
    })(testData[i]);
}

steps.push(function() { t.login({}, t.nextStep()); });
steps.push(function() { t.endAsync(); });

t.runAsync(steps, testData.length * 600000);

})(jQuery);
