#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 79;
use Test::Socialtext::Fatal;

################################################################################
# Fixtures: db
# - need a DB, but don't care what's in it.
fixtures(qw( db ));

use_ok 'Socialtext::Group';

################################################################################
# TEST: Group has no Users; it's a lonely, lonely group.
group_with_no_users: {
    my $group = create_test_group();
    my $users = $group->users();

    isa_ok $users, 'Socialtext::MultiCursor', 'got a list of users';
    is $users->count(), 0, '... with the correct count';
}

################################################################################
# TEST: Group has some Users
group_has_users: {
    my $group    = create_test_group();
    my $user_one = create_test_user();
    my $user_two = create_test_user();

    $group->add_user(user => $user_one);
    $group->add_user(user => $user_two);

    my $users = $group->users();
    isa_ok $users, 'Socialtext::MultiCursor', 'got a list of users';
    is $users->count(), 2, '... with the correct count';
    isa_ok $users->next(), 'Socialtext::User', '... queried User';
}

################################################################################
# TEST: Group has some Users, get their User Ids
group_has_users_get_user_ids: {
    my $group    = create_test_group();
    my $user_one = create_test_user();
    my $user_two = create_test_user();

    $group->add_user(user => $user_one);
    $group->add_user(user => $user_two);

    my $user_ids = [ sort @{ $group->user_ids() } ];
    is_deeply $user_ids, [ $user_one->user_id, $user_two->user_id ],
        'Got User Ids';
}

################################################################################
# TEST: Add User to Group with default Role
add_user_to_group_with_default_role: {
    my $group = create_test_group();
    my $user  = create_test_user();

    # Group should be empty (have no Users)
    is $group->users->count(), 0, 'Group has no Users in it (yet)';

    # Add the User to the Group
    $group->add_user(user => $user);

    # Make sure the User got added properly
    is $group->users->count(), 1, '... added User to Group';

    # Make sure User was given the default Role
    my $default_role = Socialtext::Role->Member;
    my $users_role   = $group->role_for_user($user);
    is $users_role->role_id, $default_role->role_id,
        '... with Default UGR Role';
}

###############################################################################
# TEST: Add User to Group with explicit Role
add_user_to_group_with_role: {
    my $group = create_test_group();
    my $user  = create_test_user();
    my $role  = Socialtext::Role->Admin();

    # Group should be empty (have no Users)
    is $group->users->count(), 0, 'Group has no Users in it (yet)';

    # Add the User to the Group
    $group->add_user(user => $user, role => $role);

    # Make sure the User got added properly
    is $group->users->count(), 1, '... added User to Group';

    # Make sure User has correct Role
    my $users_role   = $group->role_for_user($user);
    is $users_role->role_id, $role->role_id, '... with provided Role';
}

###############################################################################
# TEST: Update User's Role in Group
update_users_role_in_group: {
    my $group = create_test_group();
    my $user  = create_test_user();
    my $role  = Socialtext::Role->Admin();

    # Add the User to the Group, with Default Role
    $group->add_user(user => $user);

    # Make sure the User was given the Default Role
    my $default_role = Socialtext::Role->Member;
    my $users_role   = $group->role_for_user($user);
    is $users_role->role_id, $default_role->role_id,
        'User has default Role in Group';

    # Update the User's Role
    $group->assign_role_to_user(user => $user, role => $role);

    # Make sure User had their Role updated
    $users_role = $group->role_for_user($user);
    is $users_role->role_id, $role->role_id, '... Role was updated';

    # Test users_as_minimal_arrayref
    my $users = $group->users_as_minimal_arrayref('member');
    is scalar(@$users), 0, 'no members';
    $users = $group->users_as_minimal_arrayref('admin');
    is scalar(@$users), 1, 'no members';
    $users = $group->users_as_minimal_arrayref();
    is scalar(@$users), 1, 'no members';
}

###############################################################################
# TEST: Get the Role for a User
get_role_for_user: {
    my $group = create_test_group();
    my $user  = create_test_user();

    # Add the User to the Group
    $group->add_user(user => $user);

    # Get the Role for the User
    my $role = $group->role_for_user($user);
    isa_ok $role, 'Socialtext::Role', 'queried Role';
}

###############################################################################
# TEST: Does this User have a Role in the Group
does_group_have_user: {
    my $group = create_test_group();
    my $user  = create_test_user();

    # Group should not (yet) have this User
    ok !$group->has_user($user), 'User does not yet have Role in Group';

    # Add the User to the Group
    $group->add_user(user => $user);

    # Now the User is in the Group
    ok $group->has_user($user), '... but has now been added';
}

###############################################################################
# TEST: Remove User from Group
remove_user_from_group: {
    my $group = create_test_group();
    my $user  = create_test_user();

    # Group should be empty to start
    ok !$group->has_user($user), 'User does not yet have Role in Group';

    # Add the User to the Group
    $group->add_user(user => $user);
    ok $group->has_user($user), '... User has been added to Group';

    # Remove the User from the Group
    $group->remove_user(user => $user);
    ok !$group->has_user($user), '... User has been removed from Group';
}

###############################################################################
# TEST: Remove User from Group, when they have *no* Role in that Group
remove_non_member_user_from_group: {
    my $group = create_test_group();
    my $user  = create_test_user();

    # Group should be empty to start
    ok !$group->has_user($user), 'User does not have Role in Group';

    # Removing a non-member User from the Group shouldn't choke.  No errors,
    # no warnings, no fatal exceptions... its basically a no-op
    ok !exception { $group->remove_user(user => $user) },
        "... removing non-member User from Group doesn't choke";
}

private_group_self_actions: {
    my $group = create_test_group();
    my $user  = create_test_user();
    my $other_user = create_test_user();
    my $yet_another_user = create_test_user();
    my $badmin = create_test_badmin();

    is $group->permission_set, 'private', "assert private group";

    # Group should be empty (have no Users)
    is $group->users->count(), 0, 'Group has no Users in it (yet)';

    # Add the User to the Group
    ok !exception {
        $group->add_user(actor => $badmin, user => $user);
    }, "business admin can add a user";
    is $group->users->count(), 1, 'still just one user';

    ok exception {
        $group->add_user(actor => $user, user => $other_user);
    }, "non admin can't add a user";

    ok exception {
        $group->add_role(actor => $user, object => $other_user, role => 'member');
    }, "non admin can't add a user";

    ok exception {
        $group->add_role(actor => $user, object => $other_user, role => 'admin');
    }, "non admin can't add a user";

    ok exception {
        $group->add_user(actor => $user, user => $other_user, role => 'admin');
    }, "non admin can't add a user";

    is $group->users->count(), 1, 'still just one user';

    ok !exception {
        $group->assign_role_to_user(
            actor => $badmin, role => 'admin', user => $user);
    }, "badmin made a group admin";

    ok !exception {
        $group->add_user(actor => $user, user => $other_user);
    }, "can now add as an admin";

    is $group->users->count(), 2, 'ok, added that time';

    $badmin->set_business_admin(0);
    $badmin->set_technical_admin(0);

    ok exception {
        $group->add_user(actor => $badmin, user => $yet_another_user);
    }, "demoted badmin can't add";

    is $group->role_for_user($other_user,direct=>1)->name, 'member', 'passenger on-board';
    ok !exception {
        $group->remove_user(actor => $other_user, user => $other_user);
    }, "passenger can abandon ship";
    is $group->users->count(), 1, ".. head count";

    ok !exception {
        $group->remove_user(actor => $user, user => $user);
    }, "captain can abandon ship (last-admin checks are done in the ReST layer)";
    is $group->users->count(), 0, "nobody left on-board";
}

self_join_group_self_actions: {
    my $acct = create_test_account_bypassing_factory();
    my $acct2 = create_test_account_bypassing_factory();
    my $group = create_test_group(account => $acct);
    my $user  = create_test_user(account => $acct);
    my $peer  = create_test_user(account => $acct);
    my $outsider = create_test_user(account => $acct2);

    $group->update_store({permission_set => 'self-join'});
    is $group->permission_set, 'self-join', "group is now self-join";

    is $group->users->count, 0;

    ok exception {
        $group->add_user(user => $outsider, actor => $outsider);
    }, "outsider can't join self-join group";
    is $group->users->count, 0;

    ok !exception {
        $group->add_user(user => $user, actor => $user);
    }, "person in same account can self-join";
    is $group->role_for_user($user,direct=>1)->name, 'member', '.. role';
    is $group->users->count, 1, '.. count';
        
    ok exception {
        $group->add_user(user => $peer, actor => $peer, role => 'admin');
    }, "can't request an admin role";
    is $group->users->count, 1, '.. count';
    
    ok !exception {
        $group->assign_role(object => $user, role => 'admin',
            actor => Socialtext::User->SystemUser);
    }, "system-user can give someone admin";
    is $group->users->count, 1, '.. count';
    is $group->role_for_user($user,direct=>1)->name, 'admin', '.. role';

    ok !exception {
        $group->add_role(object => $peer, role => 'member',
            actor => Socialtext::User->SystemUser);
    }, "system-user can add a user";
    is $group->users->count, 2, '.. count';
    is $group->role_for_user($peer,direct=>1)->name, 'member', '.. role';

    ok !exception {
        $group->add_user(user => $outsider, actor => $user);
    }, "group admin can bring in an outsider";
    is $group->users->count, 3, '.. count';
    is $group->role_for_user($outsider,direct=>1)->name, 'member', '.. role';

    ok !exception {
        $group->remove_user(user => $outsider); # default sys-user
    }, 'system-user can remove outsider';
    ok !$group->has_user($outsider), '... actually removed';
    is $group->users->count, 2, '.. count';

    ok exception {
        $group->add_user(actor => $peer, role => 'admin', user => $outsider);
    }, "member can't bring someone in as admin";
    is $group->users->count, 2, '.. count';

    ok !exception {
        $group->add_user(actor => $user, role => 'admin', user => $outsider);
    }, "group admin can bring in an outsider as an admin";
    is $group->users->count, 3, '.. count';
    is $group->role_for_user($outsider,direct=>1)->name, 'admin', '.. role';

    ok !exception {
        $group->assign_role_to_user(actor => $user, role => 'member', user => $outsider);
    }, "admin can demote a member";
    is $group->role_for_user($outsider,direct=>1)->name, 'member', '.. role';

    ok !exception {
        $group->remove_user(user => $outsider, actor => $outsider);
    }, "passenger can abandon ship";
    is $group->users->count, 2, '.. count';

    ok !exception {
        $group->remove_user(user => $peer, actor => $peer);
    }, "administrative crew can be cowards (if they're quick; i.e. not the last admin)";
    is $group->users->count, 1, '.. count';

    ok !exception {
        $group->remove_user(user => $user, actor => $user);
    }, "the captain *can* abandon ship (last-admin checks are done higher-up in the ReST layer)";
    is $group->users->count, 0, '.. count';

}

pass 'all done';
