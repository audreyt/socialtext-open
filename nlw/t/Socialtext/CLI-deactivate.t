#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 14;

BEGIN { use_ok 'Socialtext::CLI' }
use Test::Socialtext::CLIUtils qw/expect_failure expect_success/;

fixtures('db');

normal: {
    # need to set up the user to be in the right worksapces
    # and have the right perms so we can test that they go
    # away.
    my $user = create_test_user();
    my $ws1 = create_test_workspace(unique_id => "foo$^T");
    my $ws2 = create_test_workspace(unique_id => "bar$^T");
    my $username = $user->username;
    my $ws1_name = $ws1->name;
    my $ws2_name = $ws2->name;
    $user->set_technical_admin( 1 );
    $user->set_business_admin( 1 );

    expect_success(
        sub {
            Socialtext::CLI->new( argv =>
                    ['--username' => $username,
                     '--workspace' => $ws1_name] )
                ->add_workspace_admin();
        },
        qr/\Q$username\E now has the role of 'admin' in the \Q$ws1_name\E Workspace/,
        'added admin user'
    );

    expect_success(
        sub {
            Socialtext::CLI->new( argv =>
                    ['--username' => $username,
                     '--workspace' => $ws2_name] )
                ->add_member();
        },
        qr/\Q$username\E now has the role of 'member' in the \Q$ws2_name\E Workspace/,
        'added as member'
    );

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--username' => $username]
            )->deactivate_user();
        },
        qr/\Q$username\E has been removed from workspaces \Q$ws2_name\E, \Q$ws1_name\E, Removed Business Admin, Removed Technical Admin/,
        'was removed from the correct workspaces'
    );

# refresh the UserMetadata
    $user = Socialtext::User->new(username => $username);
    is(Socialtext::Account->Deleted()->account_id, $user->primary_account_id,
        "deactivated user moved into the Deleted account");
    ok !$user->is_technical_admin;
    ok !$user->is_business_admin;
}

cant_disable_important_users: {
    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [qw( --username guest )]
            )->deactivate_user();
        },
        qr/You may not deactivate/,
        'The guest user cannot be deactivated',
    );
    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [qw( --username system-user )]
            )->deactivate_user();
        },
        qr/You may not deactivate/,
        'The system-user cannot be deactivated',
    );
}
