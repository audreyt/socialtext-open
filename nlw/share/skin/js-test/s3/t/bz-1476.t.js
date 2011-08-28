var t = new Test.Visual();

t.plan(1);

t.runAsync([
    t.doCreatePage(
        ".pre\n"
      + "This page provides default sections to help get you started. You should edit this page to display information appropriate to your Workspace.\n"
      + ".pre\n\n"
      + "^^ Welcome to your Socialtext Workspace\n\n"
      + "This page provides default sections to help get you started. You should edit this page to display information appropriate to your Workspace.\n\n"
      + "One of the most important factors for successful adoption of this Workspace is participation. The more people you invite to contribute, the more your community will grow. If you are an admin, to invite members, click 'Invite others' in the menu bar at the top of the page. This takes you to a form where you enter the email addresses of the people you'd like to invite.\n"
    ),
            
    function() { 
        if (t.$('#contentColumns').hasClass('hidebox')) {
            t.$('#st-page-boxes-toggle-link').click();
        }

        t.is(
            t.$('#contentLeft').offset().top,
            t.$('#contentRight').offset().top,
            "Mixed .pre and non-.pre paragraphs should not drop contentRight"
        );

        t.endAsync();
    }
]);
