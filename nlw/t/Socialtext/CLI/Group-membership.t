#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 123;
use Test::Output qw(combined_from);
use Carp qw/confess/;
use Socialtext::CLI;
use Test::Socialtext::CLIUtils;

# Only need a DB.
fixtures(qw(db));

################################################################################
# TEST: add group to account
add_group_to_account: {
    my $group   = create_test_group();
    my $account = create_test_account_bypassing_factory();

    ok 1, 'Group is added to Account';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                        '--group'   => $group->group_id,
                        '--account' => $account->name,
                    ],
            )->add_member();
        };
    } );
    like $output, qr/.+ now has the role of 'member' in the .+ Account/,
        '... with correct message';

    my $role = $account->role_for_group($group);
    is $role->role_id => Socialtext::Role->Member()->role_id,
       '... with correct role';
}

################################################################################
# TEST: add group to account, group already exists
group_already_exists: {
    my $account = create_test_account_bypassing_factory();
    my $group = create_test_group( account => $account );

    ok 1, 'Group is not added to Account';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                        '--group'   => $group->group_id,
                        '--account' => $account->name,
                ],
            )->add_member();
        };
    } );
    like $output, qr/.+ already has the role of 'member' in the \S+ Account/,
        '... with correct message';
}

################################################################################
# TEST: remove Group from Account
remove_group_from_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    $account->add_group(group => $group);

    ok 1, 'Remove Group from Account';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'   => $group->group_id,
                    '--account' => $account->name,
                ],
            )->remove_member();
        };
    } );

    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';
    is $account->has_group( $group ) => 0, '... group is no longer in account';
}

################################################################################
# TEST: remove Group from Primary Account
remove_group_from_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group( account => $account );

    ok 1, 'Remove Group from Primary Account';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'   => $group->group_id,
                    '--account' => $account->name,
                ],
            )->remove_member();
        };
    } );

    like $output, qr/.+ is Group's Primary Account/,
        '... with correct error message';
    ok $account->has_group( $group ), '... group is still a member';
}

################################################################################
# TEST: remove Group from Account, Group is not in Account
group_is_not_in_account: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();

    ok 1, 'Remove Group that is not in Account';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'   => $group->group_id,
                    '--account' => $account->name,
                ],
            )->remove_member();
        };
    } );

    like $output, qr/.+ is not a member of .+/,
        '... with correct message';
}

################################################################################
# TEST: Group members are listed in Account membership list
group_users_in_account_membership: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group( account => $account );
    my $user    = create_test_user();
    my $email   = $user->email_address;

    ok $account->has_group( $group ), 'Group is in Account';

    $group->add_user( user => $user );
    ok $group->has_user( $user ), 'User is in Group';


    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--account' => $account->name,
                ],
            )->show_members();
        };
    } );

    like $output, qr/\Q$email\E/, 'Account lists group user';
}

################################################################################
# TEST: Account users in Groups are de-duped
group_users_in_account_membership_de_duped: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group( account => $account );
    my $user    = create_test_user( account => $account );
    my $email   = $user->email_address;

    ok $account->has_group( $group ), 'Group is in Account';

    $group->add_user( user => $user );
    ok $group->has_user( $user ), 'User is in Group';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--account' => $account->name,
                ],
            )->show_members();
        };
    } );

    my @lines = grep { /\Q$email\E/ } split(/\n/, $output);
    is scalar(@lines), 1, 'Users are de-duped for Account';
}

################################################################################
# TEST: Workspace users in Groups are de-duped
group_users_in_workspace_membership_de_duped: {
    my $workspace = create_test_workspace();
    my $user      = create_test_user();
    my $group     = create_test_group();
    my $email     = $user->email_address;

    $workspace->add_user( user => $user );
    ok $workspace->has_user( $user ), 'User is in Workspace';

    $group->add_user( user => $user );
    ok $group->has_user( $user ), 'User is in Group';

    $workspace->add_group( group => $group );
    ok $workspace->has_group( $group ), 'Group is in Workspace';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--workspace' => $workspace->name,
                ],
            )->show_members();
        };
    } );

    my @lines = grep { /\Q$email\E/ } split(/\n/, $output);
    is scalar(@lines), 1, 'Users are de-duped for Workspace';
}

################################################################################
# TEST: Account users in Groups are not displayed
group_users_in_account_membership_no_displayed: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group( account => $account );
    ok $account->has_group( $group ), 'Group is in Account';

    my $user1  = create_test_user();
    my $email1 = $user1->email_address;
    $group->add_user( user => $user1 );
    ok $group->has_user( $user1 ), 'User is in Group';

    # create another user with a _direct_ account membership
    my $user2 = create_test_user( account => $account );
    my $email2 = $user2->email_address;

    ok 1, 'All Account Users';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--account' => $account->name,
                ],
            )->show_members();
        };
    } );
    like $output, qr/\Q$email1\E/, '... lists group user';
    like $output, qr/\Q$email2\E/, '... lists direct user';

    ok 1, 'Direct Account Users';
    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--account' => $account->name,
                    '--direct',
                ],
            )->show_members();
        };
    } );
    unlike $output, qr/\Q$email1\E/, '... does not list group user';
    like $output, qr/\Q$email2\E/, '... lists direct user';
}

################################################################################
# TEST: Workspace Users with direct Roles
workspace_users_with_direct_roles: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();
    my $user1     = create_test_user();
    my $email1    = $user1->email_address;
    my $user2     = create_test_user();
    my $email2    = $user2->email_address;

    $group->add_user( user => $user1 );
    ok $group->has_user( $user1 ), 'User1 is in Group';

    $workspace->add_user( user => $user2 );
    ok $workspace->has_user( $user2 ), 'User2 is in Workspace';

    $workspace->add_group( group => $group );
    ok $workspace->has_group( $group ), 'Group is in Workspace';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--workspace' => $workspace->name,
                ],
            )->show_members();
        }
    } );
    like $output, qr/\Q$email1\E/,
        '... lists group user without direct membership';
    like $output, qr/\Q$email2\E/,
        '... lists direct user with indirect membership';

    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--workspace' => $workspace->name,
                    '--direct',
                ],
            )->show_members();
        };
    } );

    unlike $output, qr/\Q$email1\E/,
       '... does not list group user with indirect membership';
    like $output, qr/\Q$email2\E/,
        '... lists direct user with direct membership';
}

###############################################################################
# TEST: remove a Group from a WS.
remove_group_from_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();

    # Group shouldn't be a member of our Test Account yet
    ok !$account->has_group($group), 'Group not in test Account (yet)';

    # Add the Group to the WS, giving the Group a GAR in the test Account
    $workspace->add_group(group => $group);
    ok $workspace->has_group($group), '... added Group to test WS';
    ok $account->has_group($group),   '... giving Group a Role in Account';

    # Remove the Group from the WS
    ok 1, 'Remove Group from Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';

    ok !$workspace->has_group($group), '... Group is no longer in test WS';
    ok !$account->has_group($group),   '... and is no longer in test Account';
}

###############################################################################
# TEST: remove a Group from a WS, Group still has other Role in Account
remove_group_from_workspace_keep_gar: {
    my $account = create_test_account_bypassing_factory();
    my $ws_one  = create_test_workspace(account => $account);
    my $ws_two  = create_test_workspace(account => $account);
    my $group   = create_test_group();

    # Group shouldn't be a member of our Test Account yet
    ok !$account->has_group($group), 'Group not in test Account (yet)';

    # Add the Group to both WSs, giving the Group a GAR in the test Account
    $ws_one->add_group(group => $group);
    $ws_two->add_group(group => $group);
    ok $ws_one->has_group($group),  '... added Group to WS one';
    ok $ws_two->has_group($group),  '... added Group to WS two';
    ok $account->has_group($group), '... giving Group a Role in Account';

    # Remove the Group from one of the WSs
    ok 1, 'Remove Group from Workspace, when Group has other Role in Acct';
    my $output = combined_from( sub {
        eval {
        Socialtext::CLI->new(
            argv => [
                '--group'     => $group->group_id,
                '--workspace' => $ws_one->name,
            ],
        )->remove_member();
        };
    } );
    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';

    ok !$ws_one->has_group($group),  '... Group is no longer in WS one';
    ok  $ws_two->has_group($group),  '... but is still in WS two';
    ok  $account->has_group($group), '... and is still in Account';
}

###############################################################################
# TEST: remove a Group from a WS, Group doesn't exist
remove_bogus_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group_id  = 1234567890,

    ok 1, 'Remove bogus Group from Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/No group with ID $group_id/,
        '... fails with correct output';
}

###############################################################################
# TEST: remove a Group from a WS, WS doesn't exist
remove_group_from_bogus_workspace: {
    my $group   = create_test_group();
    my $ws_name = 'bogus-ws-that-doesnt-exist';

    ok 1, 'Remove Group from bogus Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $ws_name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/No workspace named "$ws_name" could be found/,
        '... fails with correct message';
}

###############################################################################
# TEST: remove a Group from a WS, Group isn't a member in the WS
remove_nonmember_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();

    ok 1, 'Remove non-member Group from Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/.+ is not a member of .+/,
        '... fails with correct message';
}
###############################################################################
# TEST: remove a Group from a WS.
###############################################################################
# TEST: remove a Group from a WS, Group still has other Role in Account
remove_group_from_workspace_keep_gar: {
    my $account = create_test_account_bypassing_factory();
    my $ws_one  = create_test_workspace(account => $account);
    my $ws_two  = create_test_workspace(account => $account);
    my $group   = create_test_group();

    # Group shouldn't be a member of our Test Account yet
    ok !$account->has_group($group), 'Group not in test Account (yet)';

    # Add the Group to both WSs, giving the Group a GAR in the test Account
    $ws_one->add_group(group => $group);
    $ws_two->add_group(group => $group);
    ok $ws_one->has_group($group),  '... added Group to WS one';
    ok $ws_two->has_group($group),  '... added Group to WS two';
    ok $account->has_group($group), '... giving Group a Role in Account';

    # Remove the Group from one of the WSs
    ok 1, 'Remove Group from Workspace, when Group has other Role in Acct';
    my $output = combined_from( sub {
        eval {
        Socialtext::CLI->new(
            argv => [
                '--group'     => $group->group_id,
                '--workspace' => $ws_one->name,
            ],
        )->remove_member();
        };
    } );
    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';

    ok !$ws_one->has_group($group),  '... Group is no longer in WS one';
    ok  $ws_two->has_group($group),  '... but is still in WS two';
    ok  $account->has_group($group), '... and is still in Account';
}

###############################################################################
# TEST: remove a Group from a WS, Group doesn't exist
remove_bogus_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group_id  = 1234567890,

    ok 1, 'Remove bogus Group from Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/No group with ID $group_id/,
        '... fails with correct output';
}

###############################################################################
# TEST: remove a Group from a WS, WS doesn't exist
remove_group_from_bogus_workspace: {
    my $group   = create_test_group();
    my $ws_name = 'bogus-ws-that-doesnt-exist';

    ok 1, 'Remove Group from bogus Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $ws_name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/No workspace named "$ws_name" could be found/,
        '... fails with correct message';
}

###############################################################################
# TEST: remove a Group from a WS, Group isn't a member in the WS
remove_nonmember_group_from_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();

    ok 1, 'Remove non-member Group from Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    like $output, qr/.+ is not a member of .+/,
        '... fails with correct message';
}
###############################################################################
# TEST: add a Group to a WS.
add_group_to_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace( account => $account );
    my $group     = create_test_group();

    ok !$account->has_group( $group ), 'Group has no Role in Account';

    ok 1, 'Add Group to Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_member();
        };
    } );
    like $output, qr/.+ now has the role of 'member' in the .+ Workspace/,
        '... succeeds with correct message';

    my $role = $workspace->role_for_group($group);
    ok $role, '... Group has role';
    is $role->name, Socialtext::Role->Member()->name,
        '... ... that is a member';

    $role = $account->role_for_group($group);
    ok $role, "... Group has role in Workspace's Account";
    is $role->name, 'member',
        '... ... that is a member';
}

###############################################################################
# TEST: add a Group to a WS, Group doesn't exist
add_non_existent_group_to_workspace: {
    my $workspace = create_test_workspace();

    ok 1, 'Add non-existent Group to Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => 0,
                    '--workspace' => $workspace->name,
                ],
            )->add_member();
        };
    } );
    like $output, qr/No group with ID 0/,
        '... correct error message';
}

###############################################################################
# TEST: add a Group to a WS, WS doesn't exist
add_group_to_non_existent_workspace: {
    my $group = create_test_group();

    ok 1, 'Add Group to non-existent Workspace';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => 'enosuchworkspace',
                ],
            )->add_member();
        };
    } );
    like $output, qr/No workspace named .+ could be found/,
        '... correct error message';
}
###############################################################################
# TEST: add a Group to a WS, Group is already a member in the WS
group_is_already_member_of_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();

    $workspace->add_group( group => $group );
    my $role = $workspace->role_for_group($group);

    ok $role, 'Group has role in workspace';
    is $role->name, Socialtext::Role->Member()->name,
        '... role is member';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_member();
        };
    } );
    like $output, qr/.+ already has the role of 'member' in the \S+ Workspace/,
        'Group already has role error message';
}

###############################################################################
# TEST: add a Group to a WS, Group is already an admin in the WS
group_is_already_admin_of_workspace: {
    my $workspace = create_test_workspace();
    my $group     = create_test_group();
    my $admin     = Socialtext::Role->Admin();

    $workspace->add_group( group => $group, role => $admin );
    my $role = $workspace->role_for_group($group);

    ok $role, 'Group has role in workspace';
    is $role->name, $admin->name,
        '... role is admin';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_member();
        };
    } );
    like $output, qr/.+ already has the role of 'admin' in the \S+ Workspace/,
        'Group already has role error message';
}

###############################################################################
# TEST: add a Group as admin to a WS
add_group_as_admin_to_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();

    ok !$account->has_group( $group ), 
        'Group does not have Role in Account';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_workspace_admin();
        };
    } );
    like $output, qr/.+ now has the role of 'admin' in the .+ Workspace/,
        'Group added as admin message';
    my $role = $workspace->role_for_group($group);
    ok $role, 'Group has Role in Workspace';
    is $role->name, Socialtext::Role->Admin()->name,
        '... Role is member';

    $role = $account->role_for_group($group);
    ok $role, 'Group has Role in Account';
    is $role->name, 'member', '... Role is member';
}

###############################################################################
# TEST: remove a Group as Admin from a WS
remove_group_as_admin_from_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();

    # Add Group as Admin to WS
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_workspace_admin();
        };
    } );
    like $output, qr/.+ now has the role of 'admin' in the .+ Workspace/,
        'Group added as Admin to WS';
    my $role = $workspace->role_for_group($group);
    ok $role, 'Group has Role in Workspace';
    is $role->name, Socialtext::Role->Admin()->name,
        '... Role is admin';

    # Remove Group as Admin from WS
    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_workspace_admin();
        };
    } );
    like $output, qr/.+ no longer has the role of 'admin' in the .+ Workspace/,
        '... Group removed as Admin in the WS';

    $role = $workspace->role_for_group($group);
    is $role->name, Socialtext::Role->Member()->name,
        '... ... but is still a Member in the WS';
}

###############################################################################
# TEST: add a Group as admin to a WS, Group was already a member.
add_member_group_as_admin_to_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();

    $workspace->add_group( group => $group );
    my $role = $workspace->role_for_group($group);
    ok $role, 'Group has Role in Workspace';
    is $role->name, Socialtext::Role->Member()->name,
        '... Role is member';

    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->add_workspace_admin();
        };
    } );
    warn $@ if $@;
    like $output, qr/.+ now has the role of 'admin' in the .+ Workspace/,
        'Group added as admin message';
    $role = $workspace->role_for_group($group);
    ok $role, 'Group has Role in Workspace';
    is $role->name, Socialtext::Role->Admin()->name,
        '... Role is admin';
}

###############################################################################
# TEST: add a person in a Group to a WS, add Group to the ws, remove person,
# person remains in ws, with special warning message
group_member_remains_in_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user    = create_test_user();
    my $email   = $user->email_address;
    my $member = Socialtext::Role->Member();
    my $impersonator = Socialtext::Role->Impersonator();

    $group->add_user( user => $user );
    $workspace->add_user( user => $user );
    $workspace->add_group( group => $group );
    ok 1, 'Remove user in workspace directly and via group';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--email'     => $email,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    my $membername = $member->name;
    like $output, qr/.+ now has the role of 'member' in .+ due to membership in a group/, 
        '... with correct message';

    my $role = $workspace->role_for_user($user);
    is $role->name => $member->name, 'User still has member role in workspace';

    $workspace->remove_group( group => $group);
    $workspace->add_group( group => $group, role => $impersonator );
    $workspace->add_user( user => $user );
    
    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--email'     => $email,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );
    my $impersonatorname = $impersonator->name;
    like $output, qr/.+ now has the role of 'impersonator' in .+ due to membership in a group/, 
        '... with correct message';

    $role = $workspace->role_for_user($user);
    is $role->name => $impersonator->name, 'User still has member role in workspace';
    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );

    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';
    is $account->has_group( $group ) => 0, '... group is no longer in account';

    ok !$workspace->role_for_user($user), ' ... user no longer in workspace';
}

###############################################################################
# TEST: add a person as ws admin in a Group to a WS, add Group to the ws with 
# admin role, remove person as ws admin, person remains w/admin role, 
# with special warning message
group_member_remains_admin_in_workspace: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user      = create_test_user();
    my $email     = $user->email_address;
    my $admin     = Socialtext::Role->Admin();

    $group->add_user( user => $user );
    $workspace->add_group( group => $group, role => $admin );
    {
        my $role = $workspace->role_for_user($user);
        is $role->name, 'admin', 'user has admin via group';
    }


    $workspace->add_user( user => $user, role => $admin );
    ok 1, 'Remove user as ws-admin in workspace directly and via group';
    my $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--email'     => $email,
                    '--workspace' => $workspace->name,
                ],
            )->remove_workspace_admin();
        };
    } );

    warn $@ if $@;
    like $output, qr/.+ now has the role of 'admin' in .+ due to membership in a group/, 
        '... with correct message';

    my $role = $workspace->role_for_user($user);
    is $role->name => $admin->name, 'User still has admin role in workspace';
    
    $output = combined_from( sub {
        eval {
            Socialtext::CLI->new(
                argv => [
                    '--group'     => $group->group_id,
                    '--workspace' => $workspace->name,
                ],
            )->remove_member();
        };
    } );

    like $output, qr/.+ is no longer a member of .+/,
        '... with correct message';
    is $account->has_group( $group ) => 0, '... group is no longer in account';

    is $workspace->role_for_user($user)->name => 'member', ' ... user still a member in workspace';

}


