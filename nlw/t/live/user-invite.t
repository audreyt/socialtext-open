#!perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Live fixtures => ['admin'];
# Importing Test::Socialtext will cause it to create fixtures now, which we
# want to happen want to happen _after_ Test::Live stops any running
# Apache instances, and all we really need here is Test::More.
use Test::More;
use Socialtext::Workspace;

plan tests => 44;

my $live = Test::Live->new();
my $base_uri = $live->base_url;
$live->log_in();

{
    $live->mech()->post(
        "$base_uri/admin/index.cgi", {
            action        => 'users_invite',
            Button        => 'Invite',
            users_new_ids => <<'EOF',
DevNull LastName 3 <devnull3@socialtext.com>, invalid1
invalid2
DevNull LastName 4 <devnull4@socialtext.com>, DevNull LastName 5 <devnull5@socialtext.com>
mailto:devnull6@socialtext.com
<devnull7@socialtext.com>, devnull8@socialtext.com
EOF
        },
    );
    my $content = $live->mech()->content();
    like( $content, qr/following users/,
          'check server response for success message' );

    my $ws = Socialtext::Workspace->new( name => 'admin' );
    for my $usernum (3 .. 8) {
        my $username = "devnull$usernum\@socialtext.com";

        like( $content, qr/\Q$username\E/, "$username was at least acknowledged");

        my $user = Socialtext::User->new( username => $username );
        ok( $user, "$username exists in database" );
        ok( $ws->has_user( $user ),
            "$username is a member of the admin workspace" );
        is( $user->creator()->username(), 'devnull1@socialtext.com',
            "$username has devnull1\@socialtext.com as creator" );
        is( $user->email_address, $username, "correct email address" );
        if ($usernum <= 5) {
            is( $user->first_name, "DevNull", "correct first name" );
            is( $user->last_name, "LastName $usernum", "correct last name" );
        }
        else {
            is( $user->first_name, "devnull$usernum", "correct guessed first name" );
            is( $user->last_name, '', "no last name" );
        }
    }

    like $content, 
        qr{<p>The following email addresses were invalid</p>\s+<ul>\s+<li>\s*invalid1\s*</li>\s+<li>\s*invalid2\s*</li>}s,
        "invalid addresses identified";
}
