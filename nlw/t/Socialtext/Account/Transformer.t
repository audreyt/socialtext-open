#!/user/bin/perl
# @COPYRIGHT@
use strict;
use warnings;

use Test::Socialtext tests => 42;
use Socialtext::Role;
use Socialtext::User;
use Socialtext::Workspace;

$ENV{TEST_LESS_VERBOSE} = 1;
fixtures('db');

use_ok 'Socialtext::Account::Transformer';

my $member = Socialtext::Role->Member();
my $admin  = Socialtext::Role->Admin();

my $other_account = create_test_account_bypassing_factory();
my $into_account  = create_test_account_bypassing_factory();
my $old_account   = create_test_account_bypassing_factory();
my $old_workspace = create_test_workspace(account => $old_account);

# np == "not primary"
my $acct_admin         = create_test_user(account => $old_account);
my $acct_member_np     = create_test_user(account => $other_account);
my $ws_member          = create_test_user(account => $old_account);
my $ws_admin_np        = create_test_user(account => $other_account);
my $admin_group        = create_test_group(account => $old_account);
my $member_group_np    = create_test_group(account => $other_account);
my $ws_member_group    = create_test_group(account => $old_account);
my $ws_admin_group_np  = create_test_group(account => $other_account);
my $multi_roles        = create_test_user(account => $other_account);

my $role  = undef;
my $group = undef;

# Setup
{
    $old_workspace->add_user(user => $ws_member, role => $member);
    $role = $old_workspace->role_for_user($ws_member, {direct => 1});
    ok $role && $role->role_id == $member->role_id,
        'ws member user has member role in old workspace';

    $old_workspace->add_user(user => $ws_admin_np, role => $admin);
    $role = $old_workspace->role_for_user($ws_admin_np, {direct => 1});
    ok $role && $role->role_id == $admin->role_id,
        'ws member user (non-primary) has member role in old workspace';

    $old_workspace->add_group(group => $ws_member_group, role => $member);
    $role = $old_workspace->role_for_group($ws_member_group, {direct => 1});
    ok $role && $role->role_id == $member->role_id,
        'ws member group has member role in old workspace';

    $old_workspace->add_group(group => $ws_admin_group_np, role => $admin);
    $role = $old_workspace->role_for_group($ws_admin_group_np, {direct => 1});
    ok $role && $role->role_id == $admin->role_id,
        'ws admin group (non-primary) has admin role in old workspace';

    $old_account->add_user(user => $acct_member_np, role => $member);
    $role = $old_account->role_for_user($acct_member_np, {direct => 1});
    ok $role && $role->role_id == $member->role_id,
        'account member user (non-primary) has member role in old account';

    $old_account->add_group(group => $member_group_np, role => $member);
    $role = $old_account->role_for_group($member_group_np, {direct => 1});
    ok $role && $role->role_id == $member->role_id,
        'member group (non-primary) is a member in old account';

    $old_account->assign_role_to_group(group => $admin_group, role => $admin);
    $role = $old_account->role_for_group($admin_group, {direct => 1});
    ok $role && $role->role_id == $admin->role_id,
        'admin group (non-primary) is an admin in old account';

    $old_account->assign_role_to_user(user => $acct_admin, role => $admin);
    $role = $old_account->role_for_user($acct_admin, {direct => 1});
    ok $role && $role->role_id == $admin->role_id,
        'account admin user is an admin in old account';

    $old_account->add_user(user => $multi_roles, role => $admin);
    $role = $old_account->role_for_user($multi_roles, {direct => 1});
    ok $role && $role->role_id == $admin->role_id,
        'multi roles user is a direct admin in the old account';

    $old_workspace->add_user(user => $multi_roles, role => $member);
    $role = $old_workspace->role_for_user($multi_roles, {direct => 1});
    ok $role && $role->role_id == $member->role_id,
        'multi roles user is a direct member in the old workspace';
}

# Do work
{
    my $obj = Socialtext::Account::Transformer->new(
        into_account_name => $into_account->name);
    $obj->acct2group(account_name => $old_account->name, insane => 1);
}

# Group was created
# Workspace was moved to new account.
# old account was deleted.
{
    $group = Socialtext::Group->GetGroup({
            driver_group_name => $old_account->name,
            primary_account_id => $into_account->account_id,
            created_by_user_id => Socialtext::User->SystemUser->user_id,
    });
    ok $group, 'new group was created with correct attrs';

    $role = $into_account->role_for_group($group, { direct => 1 });
    ok $role && $role->role_id == $member->role_id,
        'new group has a member role in into account';

    # Freshen workspace
    $old_workspace = Socialtext::Workspace->new(
        workspace_id => $old_workspace->workspace_id);

    is $old_workspace->account_id, $into_account->account_id,
        'old workspace has been moved to into account';

    # Freshen account
    $old_account = Socialtext::Account->new(
        account_id => $old_account->account_id);

    ok !$old_account, 'old account has been deleted';
}

# Old account member has direct member role in new group, into account
# This user's primary account was old_account, and should update
{
    check_transform(
        title           => "account admin user",
        user_id         => $acct_admin->user_id,
        exp_group_role  => $admin,
        group_attr      => { direct => 1 },
        primary_account => $into_account,
    );
}

# Old account member has direct member role in new group, 
# and an indirect member role in into account
# This user's primary account was not old_account, it should not update.
{
    check_transform(
        title           => 'account member user (non-primary)',
        user_id         => $acct_member_np->user_id,
        group_attr      => { direct => 1 },
        primary_account => $other_account,
    );
}

# Old account group has a direct member role in new group,
# and an indirect member role in into account,
# The group's primary account is also updated.
{
    check_transform(
        title           => 'account admin group',
        group_id        => $admin_group->group_id,
        exp_group_role  => $admin,
        group_attr      => { direct => 1 },
        primary_account => $into_account,
    );
}

# Old account group np has a direct member role in new group,
# and an indirect member role in into account,
# The group's primary account is not updated.
{
    check_transform(
        title           => 'account member group (non-primary)',
        group_id        => $member_group_np->group_id,
        group_attr      => { direct => 1 },
        primary_account => $other_account,
    );
}

# Old workspace member has direct member role in new group,
# indirect role in new account.
# Primary account is into account
{
    check_transform(
        title           => 'workspace member user',
        user_id         => $ws_member->user_id,
        group_attr      => { direct => 1 },
        primary_account => $into_account,
    );
}

# Old workspace member np has direct member role in new group,
# indirect role in new account.
# Primary account remains other account.
{
    check_transform(
        title           => 'workspace admin user (non-primary)',
        user_id         => $ws_admin_np->user_id,
        group_attr      => { direct => 1 },
        primary_account => $other_account,
    );
}

# Old workspace group has a direct member role in the new group,
# indirect role in the new account,
# Primary account is updated to new account.
{
    check_transform(
        title           => 'workspace member group',
        group_id        => $ws_member_group->group_id,
        group_attrs     => { direct => 1 },
        primary_account => $into_account,
    );
}

# Old workspace group np has a direct member role in the new group,
# indirect role in the new account,
# Primary account remains other account
{
    check_transform(
        title           => 'workspace admin group (non-primary)',
        group_id        => $ws_admin_group_np->group_id,
        group_attrs     => { direct => 1 },
        primary_account => $other_account,
    );
}

# Multi-role user should have a direct admin role in the new group
# indirect member role in new account,
# primary account remains other account.
{
    check_transform(
        title           => 'multi role user',
        user_id         => $multi_roles->user_id,
        exp_group_role  => $admin,
        group_attrs     => { direct => 1 },
        primary_account => $other_account,
    );
}

exit;
################################################################################
sub check_transform {
    my %p = @_;

    my $exp_grp_role = $p{exp_group_role} || $member;
    my $exp_grp_name = $exp_grp_role->name;
    my $exp_grp_id   = $exp_grp_role->role_id;
    my $group_attr   = $p{group_attr} || {};

    my $exp_acct_role = $p{exp_acct_role} || $member;
    my $exp_acct_name = $exp_acct_role->name;
    my $exp_acct_id   = $exp_acct_role->role_id;
    my $acct_attr     = $p{acct_attr} || {};

    my $thing;
    my $role_for;

    if ($p{user_id}) {
        $thing = Socialtext::User->new(user_id => $p{user_id});
        $role_for = 'role_for_user';
    }
    else {
        $thing = Socialtext::Group->GetGroup({group_id => $p{group_id}});
        $role_for = 'role_for_group';
    }


    my $group_role = $group->$role_for($thing, $group_attr);
    ok $group_role && $group_role->role_id == $exp_grp_id,
        "$p{title} is a $exp_grp_name in new group";

    my $acct_role  = $into_account->$role_for($thing, $acct_attr);
    ok $acct_role && $acct_role->role_id  == $exp_acct_id,
        "$p{title} is a $exp_acct_name in into account";

    is $thing->primary_account_id, $p{primary_account}->account_id,
        "$p{title} has correct primary account";
}
