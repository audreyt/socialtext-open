#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Manual;

prompt "This is a line-by-line walkthrough of every test I can think of for
workspaces.  Hopefully we can replace more and more of it with actual
automated steps.  If it tells you to do something and then stops, it's
expecting you to hit enter.  An example is now.";

sh 'dev-bin/test-env-from-scratch' unless $ENV{SLOPPY_IMPATIENT_PROGRAMMER};

sh 'prove -l t 1>test_output 2>test_errors &';

promptlines <<EOF;
Now, go to your dev server's Settings -> Create New Workspace.  First, check some error conditions: Hit 'Create' with nothing filled in.
...fill in workspace with a valid name, but keep Title blank
...fill in title, but give a short workspace name (2 chars)
...try an illegal workspace name, such as "admin"
...try a name that's illegal for mail alias reasons, such as "www-data"
...try a name with illegal chars, such as (*&)(*&#@)\$#
...ok, that'll probably do - give it a legal pair, such as Banana/banana, and click around on it a little
EOF
lswksp;

nlwrootsh "./index.cgi create_workspace abcde";
lswksp;
prompt "Now you should be able to log in to workspace abcde (user support\@socialtext.com)";
print "The following should fail because of the duplicate workspace id:\n";
nlwrootsh "./index.cgi create_workspace abcde";

nlwrootsh "./index.cgi create_workspace_full --workspace fghij --admin devnull2\@socialtext.com --logo http://www.vim.org/images/vim_header.gif";
lswksp;
promptlines <<EOF;
Now you should be able to log in to workspace fghij (user support\@socialtext.com)
...observe that the logo is changed.
...check the People link to make sure devnull2 got added as an admin.  (Note: It may be valuable to replace devnull2\@socialtext.com with your own address in this test, so the automatic-invite gets to you and make sure you can actually log in using that password)
EOF
lswksp;

promptlines <<EOF;
Now test the SalesForce URL (which will probably require you to log back in as devnull1: <your-server>/admin/index.cgi?workspace_id=klmnop&Button=Create&action=workspaces_create_full&workspace_title=Nothin+Special&user_email=devnull2\@socialtext.com&user_first_name=Devin&user_last_name=Nullington&logo_url=http://www.manelelena.com/img/tux.png
...view the workspace to make sure the logo was saved
...hit "People" to see if devnull2 was added correctly
...hit the same creation URL as above to make sure you get a "Workspace Unavailable" error.
EOF

lswksp;

prompt "If you have any idea how to test bin/create_workspace, let me know";

promptlines <<EOF;
Ok, click around on a new workspace a bit to make sure it's legitimate, then go to Settings -> This Workspace
...probably change a bunch of things at once to save time: The workspace title, set the image to existing: http://www.google.com/images/firefox/light.gif , the Team Favorites page, etc - just change 'em all and make sure that when you Save they're the same - it's up to other parts of the code to correctly respond to these options.
...notice that the Proxy only accepts input if it's in the form of https://... this should probably generate a warning, but currently doesn't.
...then check the error handling, maybe delete the workspace name. (which also doesn't seem to be getting validation at the moment)
...maybe test the image upload facility.
EOF

promptlines <<EOF;
Almost done - Make sure your "My Workspaces" box on the right is dropped down, then go to Settings -> My Workspaces
...uncheck some - observe that the box reflects the changes.
EOF

prompt "Hopefully the unit tests are done by now (hit enter to see the output)";
sh "cat test_errors test_output";
unlink qw(test_output test_errors) or die "Couldn't unlink: $!";
