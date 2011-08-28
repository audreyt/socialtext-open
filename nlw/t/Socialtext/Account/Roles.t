#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 12;
use Test::Differences;
use Test::Socialtext::User;
use Socialtext::Account::Roles;
use Socialtext::Role;

###############################################################################
# Fixtures: db
fixtures(qw( db ));

###############################################################################
# Short-hand access to some Roles.
my $Member    = Socialtext::Role->Member();
my $Admin     = Socialtext::Role->Admin();

###############################################################################
# TEST: Get Role for User; when its his Primary Account
get_role_for_user_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    my $role    = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    isa_ok $role, 'Socialtext::Role', 'Users Role in his Primary Account';
    is $role->name, $Member->name, '... is "Member"';
}

###############################################################################
# TEST: Get Role for User; explicit User/Account Role
get_role_for_user_explicit_uar: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user();

    $account->add_user(user => $user, role => $Admin);

    my $role = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    isa_ok $role, 'Socialtext::Role', 'Users explicit Role in Account';
    is $role->name, $Admin->name, '... is the assigned User/Account Role';
}

###############################################################################
# TEST: Get Role for User; User/Workspace Role, with member User/Account Role
get_role_for_user_uwr: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $user      = create_test_user();

    $workspace->add_user(user => $user, role => $Admin);

    my $role = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    isa_ok $role, 'Socialtext::Role', 'Users secondary Role in Account';
    is $role->name, $Member->name, '... is the "member" Role';
}

###############################################################################
# TEST: Get Role for User; User/Group Role and explicit Group/Account Role
get_role_for_user_gar: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();
    my $user    = create_test_user();

    $account->add_group(group => $group, role => $Admin);
    $group->add_user(user => $user, role => $Member);

    my $role = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    isa_ok $role, 'Socialtext::Role', 'Users indirect Role in Account';
    is $role->name, $Admin->name, '... is the assigned Group/Account Role';
}

###############################################################################
# TEST: Get Role for User; User/Group Role, Group/Workspace Role, with member
# Group/Account Role
get_role_for_user_gwr: {
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user      = create_test_user();

    $workspace->add_group(group => $group, role => $Admin);
    $group->add_user(user => $user, role => $Member);

    my $role = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    isa_ok $role, 'Socialtext::Role', 'Users indirect Role in Account';
    is $role->name, $Member->name, '... is the "member" Role';
}

###############################################################################
# TEST: Get Roles for User; explicit User/Account Role and a Group/Account Role
get_roles_for_user_uar_and_gar: {
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group();
    my $user    = create_test_user();

    $account->add_group(group => $group, role => $Member);
    $group->add_user(user => $user, role => $Admin);

    $account->add_user(user => $user, role => $Admin);

    my @roles = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    my @received = map { $_->name } @roles;
    my @expected = map { $_->name } ($Admin, $Member);
    eq_or_diff \@received, \@expected, 'Users Roles in Account (UAR, GAR)';
}

###############################################################################
# TEST: Get Roles for User; multiple Group/Account Roles
get_roles_for_user_multiple_gars: {
    my $account     = create_test_account_bypassing_factory();
    my $group_one   = create_test_group();
    my $group_two   = create_test_group();
    my $group_three = create_test_group();
    my $user        = create_test_user();

    $group_one->add_user(user => $user);
    $group_two->add_user(user => $user);
    $group_three->add_user(user => $user);

    $account->add_group(group => $group_one,   role => $Member);
    $account->add_group(group => $group_two,   role => $Admin);
    $account->add_group(group => $group_three, role => $Member);

    my @roles = Socialtext::Account::Roles->RolesForUserInAccount(
        user    => $user,
        account => $account,
    );
    my @received = map { $_->name } @roles;
    my @expected = map { $_->name } ($Admin, $Member);  # de-duped
    eq_or_diff \@received, \@expected, 'Users Roles in Account (multiple GARs)';
}
