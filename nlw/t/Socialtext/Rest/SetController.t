#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Role;
use Test::Socialtext tests => 36;

my $class = 'Socialtext::Rest::SetController';
use_ok $class;

fixtures(qw( db ));

# Roles to test against.
my $member = Socialtext::Role->Member();
my $admin  = Socialtext::Role->Admin();

my $actor = create_test_user();
my $wksp  = create_test_workspace();

# Exercise actions
exercise_actions: {
    my $controller = $class->new(
        actor     => $actor,
        container => $wksp,
        scopes    => ['user'],
    );

    is_deeply [sort $controller->actions()] => [qw(add remove update)],
        'all actions enabled by default';

    ok $controller->actions([qw(add update)]), 'actions is updateable';

    eval { $controller->actions([qw(illegal)]) };
    ok $@, 'dies when action is illegal';
}

# Exercise hooks
execise_hooks: {
    my $controller = $class->new(
        actor     => $actor,
        container => $wksp,
        scopes    => ['group'],
    );

    is_deeply $controller->hooks() => {}, 'no hooks are enabled by default';

    ok $controller->hooks({post_add_group => sub { "yay" }}),
        'can update hooks';
}

# Exerise scope
exercise_scope: {
    eval {
        my $controller = $class->new(
            actor     => $actor,
            container => $wksp,
            scopes    => ['illegal'],
        );
    };
    ok $@, 'dies with illegal value for scope';
}

# one at a time - we could do this with a single perspective, but to test out
# action boundaries, we'll use three separate, tightly bound, perspectives.
one_atta_time: {
    my $user1  = create_test_user();
    my $user2  = create_test_user();
    my $group1 = create_test_group();

    my %controller = ();
    for my $action (qw(add update remove)) {
        $controller{$action} = $class->new(
            actor     => $actor,
            container => $wksp,
            actions   => [$action],
            scopes    => ['user'],
        );
    }

    # Using a hash
    {
        my %hash = (user_id => $user1->user_id, role_name => $member->name);
        $controller{add}->alter_one_member(%hash);

        my $role = $wksp->role_for_user($user1);
        ok $role, 'user one was added to workspace with hash';
        is $role->role_id => $member->role_id, '... as a member';

        $hash{role_name} = $admin->name;
        $controller{update}->alter_one_member(%hash);

        $role = $wksp->role_for_user($user1);
        ok $role, 'user updated to admin with hash';
        is $role->role_id => $admin->role_id, '... as an admin';

        delete $hash{role_name};
        $controller{remove}->alter_one_member(%hash);

        ok !$wksp->has_user($user1), 'user one removed with hash';
    }

    # Using a hashref
    {
        my $ref = {user_id => $user2->user_id, role_name => $member->name};
        $controller{add}->alter_one_member($ref);

        my $role = $wksp->role_for_user($user2);
        ok $role, 'user two was added to workspace with hashref';
        is $role->role_id => $member->role_id, '... as a member';

        $ref->{role_name} = $admin->name;
        $controller{update}->alter_one_member($ref);

        $role = $wksp->role_for_user($user2);
        ok $role, 'user updated to admin with hashref';
        is $role->role_id => $admin->role_id, '... as an admin';

        $ref->{role_name} = undef;
        $controller{remove}->alter_one_member($ref);
        ok !$wksp->has_user($user1), 'user one removed with hashref';
    }

    # Doing something other than add dies (with no role == delete)
    $wksp->add_user(user => $user1, role => $member->name);
    eval { $controller{add}->alter_one_member(user_id => $user1->user_id) };
    ok $@, 'non-add operation dies';

    # Cannot break scope
    eval { 
        my %req = (group_id => $group1->group_id, role_name => 'member');
        $controller{add}->alter_one_member(%req)
    };
    ok $@, 'cannot break user scope';
}

multiple_changes: {
    my $user1 = create_test_user();
    my $user2 = create_test_user();
    my $user3 = create_test_user();

    my $controller = $class->new(
        actor     => $actor,
        container => $wksp,
        scopes    => ['user'],
    );

    $wksp->add_user(user => $user1, role => $member);
    $wksp->add_user(user => $user3, role => $member);

    my $req = [
        { user_id  => $user1->user_id,  role_name => $admin->name },
        { username => $user2->username, role_name => $member->name },
        { user_id  => $user3->user_id,  role_name => undef },
    ];
    $controller->alter_members($req);

    # check user one
    my $role = $wksp->role_for_user($user1);
    ok $role, 'user one has a role after multi-update';
    is $role->name, $admin->name, '... role is admin';

    # check user two
    $role = $wksp->role_for_user($user2);
    ok $role, 'user two has a role after multi-update';
    is $role->name, $member->name, '... role is member';

    # check user three
    $role = $wksp->role_for_user($user3);
    ok !$role, 'user three has no role after multi-update';
}

# groups one at a time.
groups_one_atta_time: {
    my $group1 = create_test_group();

    my %controller = ();
    for my $action (qw(add update remove)) {
        $controller{$action} = $class->new(
            actor     => $actor,
            container => $wksp,
            actions   => [$action],
            scopes    => ['group'],
        );
    }

    my %hash = (group_id => $group1->group_id , role_name => $member->name);
    $controller{add}->alter_one_member(%hash);

    my $role = $wksp->role_for_group($group1);
    ok $role, 'group one was added to workspace with hash';
    is $role->role_id => $member->role_id, '... as a member';

    $hash{role_name} = $admin->name;
    $controller{update}->alter_one_member(%hash);

    $role = $wksp->role_for_group($group1);
    ok $role, 'group updated to admin with hash';
    is $role->role_id => $admin->role_id, '... as an admin';

    delete $hash{role_name};
    $controller{remove}->alter_one_member(%hash);

    ok !$wksp->has_group($group1), 'group one removed with hash';
}

# Multi-scopes
multi_scopes: {
    my $user1  = create_test_user();
    my $group1 = create_test_group();

    my $controller = $class->new(
        actor     => $actor,
        container => $wksp,
    );

    # Add user and group
    $controller->alter_members([
        { user_id  => $user1->user_id,   role_name => $admin->name },
        { group_id => $group1->group_id, role_name => $member->name },
    ]);

    # Check user
    my $role = $wksp->role_for_user($user1);
    ok $role, 'user one added in multi-scope';
    is $role->role_id => $admin->role_id, '... as a admin';

    # Check group
    $role = $wksp->role_for_group($group1);
    ok $role, 'group one added in multi-scope';
    is $role->role_id => $member->role_id, '... as a member';
}

# Hooks
hooks: {
    my $user1 = create_test_user();

    my $controller = $class->new(
        actor     => $actor,
        container => $wksp,
        scopes    => ['user'],
    );

    # Add some hooks one at a time.
    $controller->hooks()->{post_user_add}    = sub { "yay" };
    $controller->hooks()->{post_user_update} = sub { "whoo hoo" };
    $controller->hooks()->{post_user_remove} = sub { "hooray" };

    # post_add_user
    my %req = (user_id => $user1->user_id, role_name => 'member');
    my $res = $controller->alter_one_member(%req);
    is $res => 'yay', 'post_add_user hook was called';

    # post_update_user
    $req{role_name} = $admin->name;
    $res = $controller->alter_one_member(%req);
    is $res => 'whoo hoo', 'post_update_user hook was called';

    # post_delete_user
    delete $req{role_name};
    $res = $controller->alter_one_member(%req);
    is $res => 'hooray', 'post_delete_user hook was called';
}

exit;
