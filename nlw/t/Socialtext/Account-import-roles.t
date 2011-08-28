#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 180;
use Test::Differences;
use Test::Output qw/stderr_is/;
use Socialtext::CLI;
use Socialtext::SQL qw/:exec/;
use Test::Socialtext::User;
use Test::Socialtext::Group;
use Test::Socialtext::Workspace;
use Test::Socialtext::Account qw/export_and_reimport_account/;
use Test::Socialtext::CLIUtils qw(expect_success);

fixtures(qw(db));

###############################################################################
# Grab short-hand versions of the Roles we're going to use
my $Member       = Socialtext::Role->Member();
my $Admin        = Socialtext::Role->Admin();
my $Impersonator = Socialtext::Role->Impersonator();

###############################################################################
# TEST: Account export/import preserves GAR, when Group has this Account as
# its Primary Account.
account_import_preserves_gar_primary_account: {
    pass 'TEST: Preserves GARs; Groups Primary Account';
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group(account => $account);

    # Export and re-import the Account; GAR should be preserved
    export_and_reimport_account(
        account => $account,
        groups  => [$group],
    );
}

###############################################################################
# TEST: Account export/import preserves GAR, when Group has a Role in this
# Account (but its not the Groups Primary Account).
account_import_preserves_gar: {
    pass 'TEST: Preserves GARs; Group has Role in Account';
    my $account    = create_test_account_bypassing_factory();
    my $acct_name  = $account->name();

    my $group      = create_test_group();
    my $group_name = $group->driver_group_name();

    my $impersonator      = create_test_group();
    my $impersonator_name = $impersonator->driver_group_name();

    # Give the Group a direct Role in the Account
    $account->add_group(group => $group, role => $Member);
    $account->add_group(group => $impersonator, role => $Impersonator);

    # Export and re-import the Account; GAR should be preserved
    export_and_reimport_account(
        account => $account,
        groups  => [$group, $impersonator],
    );
}

###############################################################################
# TEST: Account export/import preserves GWRs/GARs
#
# Group can have an *indirect* Role in an Account by virtue of being a member
# in a Workspace that lives within the Account.  Make sure that the Role is
# preserved across export/import.
account_import_preserves_gwrs: {
    pass 'TEST: Preserves GWRs/GARs';
    my $account    = create_test_account_bypassing_factory();
    my $acct_name  = $account->name();

    my $workspace  = create_test_workspace(account => $account);
    my $ws_name    = $workspace->name();

    my $group      = create_test_group();
    my $group_name = $group->driver_group_name();

    # Give the Group a Role in a Workspace, indirectly giving it a Role in the
    # Account.
    $workspace->add_group(group => $group, role => $Admin);

    # Export and re-import the Account; GWRs/GARs should be preserved
    export_and_reimport_account(
        account    => $account,
        groups     => [$group],
        workspaces => [$workspace],
    );
}

###############################################################################
# TEST: Account export/import preserves GARs + GWRs/GARs
#
# Group can have both a *direct* and an *indirect* Role in an Account.  By the
# time it ends up in the DB its just a single GAR entry, but this test also
# verifies that the GWR was properly preserved.
account_import_preserves_direct_and_indirect_group_roles: {
    pass 'TEST: Preserves GARs + GWRs/GARs';
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name();

    my $workspace = create_test_workspace(account => $account);
    my $ws_name   = $workspace->name();

    my $group     = create_test_group();

    # Give the Group both a direct and an indirect Role in the Account.
    $account->add_group(group => $group, role => $Member);
    $workspace->add_group(group => $group);

    # Export and re-import the Account; GWRs/GARs should be preserved
    export_and_reimport_account(
        account    => $account,
        groups     => [$group],
        workspaces => [$workspace],
    );
}

###############################################################################
# TEST: Account export/import preserves multiple GWRs/GARs
#
# Group can have multiple *indirect* Roles in an Account.  Make sure that
# they're all preserved across export/import.
account_import_preserves_multiple_indirect_roles: {
    pass 'TEST: Preserves multiple GWRs/GARs';
    my $account = create_test_account_bypassing_factory();
    my $ws_one  = create_test_workspace(account => $account);
    my $ws_two  = create_test_workspace(account => $account);
    my $group   = create_test_group();

    # Give the Group some Roles in multiple Workspaces
    $ws_one->add_group(group => $group, role => $Member);
    $ws_two->add_group(group => $group, role => $Admin);

    # Export and re-import the Account
    export_and_reimport_account(
        account    => $account,
        groups     => [$group],
        workspaces => [$ws_one, $ws_two],
    );
}

###############################################################################
# TEST: Account export/import preserves UAR, when User has this Account as its
# Primary Account.
account_import_preserves_uar_primary_account: {
    pass 'TEST: Preserves UARs; Users Primary Account';
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    # Export and re-import the Account; UAR should be preserved
    export_and_reimport_account(
        account => $account,
        users   => [$user],
    );
}

###############################################################################
# TEST: preserve direct UAR
#
# User can have a *direct* Role in an Account (which as of 2009-10-22 is only
# supported via their "Primary Account").  Make sure that the Role is
# preserved across export/import.
#
# Users can also have a membership in an Account, which should also be
# preserved across export/import.
account_import_preserves_uar: {
    pass 'TEST: Preserves direct UAR';
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name();

    my $user      = create_test_user();
    my $user_name = $user->username();

    my $impersonator      = create_test_user();
    my $impersonator_name = $impersonator->username();

    my $acct_admin      = create_test_user();
    my $acct_admin_name = $acct_admin->username();

    # give the User a direct Role in the Account
    $account->add_user(user => $user, role => $Member);
    $account->add_user(user => $impersonator, role => $Impersonator);
    $account->add_user(user => $acct_admin, role => $Admin);

    # Export and re-import the Account
    export_and_reimport_account(
        account => $account,
        users   => [$user, $impersonator, $acct_admin],
    );

    # Users should have the correct Role in the Account
    $account = Socialtext::Account->new(name => $acct_name);
    isa_ok $account, 'Socialtext::Account', '... found re-imported Account';

    check_member: {
        my $found = Socialtext::User->new(username => $user_name);
        isa_ok $found, 'Socialtext::User', '... found re-imported User';

        my $role = $account->role_for_user($found);
        ok defined $role, '... User has Role in Account';
        is $role->name, $Member->name, '... ... with *correct* Role';
    }

    check_impersonator: {
        my $found = Socialtext::User->new(username => $impersonator_name);
        isa_ok $found, 'Socialtext::User', '... found re-imported Impersonator';

        my $role = $account->role_for_user($found);
        ok defined $role, '... Impersonator has Role in Account';
        is $role->name, $Impersonator->name, '... ... Impersonator Role';
    }

    check_account_admin: {
        my $found = Socialtext::User->new(username => $acct_admin_name);
        isa_ok $found, 'Socialtext::User', '... found re-imported Account Admin';

        my $role = $account->role_for_user($found);
        ok defined $role, '... Impersonator has Role in Account';
        is $role->name, $Admin->name, '... ... Admin Role';
    }
}

###############################################################################
# TEST: preserve indirect UWR
#
# User can have an *indirect* Role in an Account by virtue of being a member
# in a Workspace that lives within the Account.  Make sure that the Role is
# preserved across export/import.
account_import_preserves_uwr: {
    pass 'TEST: Preserves indirect UWR';
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name();

    my $workspace = create_test_workspace(account => $account);
    my $ws_name   = $workspace->name();

    my $user      = create_test_user();
    my $user_name = $user->username();

    # PRE-CHECK: User shouldn't be in our test Account
    ok !$account->has_user($user), '... User not in test Account (yet)';

    # give the User a Role in the Workspace, which gives them an *indirect*
    # Role in the Account.
    $workspace->add_user(user => $user, role => $Member);

    # User should now be in the test Account
    my $orig_role = $account->role_for_user($user);
    ok defined $orig_role , '... User now has a Role in the Account';

    # Export and re-import the Account; UWRs/UARs should be preserved
    export_and_reimport_account(
        account    => $account,
        workspaces => [$workspace],
        users      => [$user],
    );

    # User should have the correct Role in the Account
    $account = Socialtext::Account->new(name => $acct_name);
    isa_ok $account, 'Socialtext::Account', '... found re-imported Account';

    $user = Socialtext::User->new(username => $user_name);
    isa_ok $user, 'Socialtext::User', '... found re-imported User';

    my $role = $account->role_for_user($user);
    ok defined $role, '... User has Role in Account';
    is $role->name, $orig_role->name, '... ... with *correct* Role';
}

###############################################################################
# Test: preserve indirect UGR/GAR
#
# User can have an *indirect* Role in an Account by virtue of being a member
# of a Group that happens to have a Role in the Account.  Make sure that Role
# is preserved across export/import.
account_import_preserves_user_indirect_role_through_group: {
    pass 'TEST: Preserves UGRs/GARs';
    my $account = create_test_account_bypassing_factory();
    my $group   = create_test_group(account => $account);
    my $user    = create_test_user();

    # Add the User to the Account through a Group membership.
    $group->add_user(user => $user);

    # Export and re-import the Account
    export_and_reimport_account(
        account    => $account,
        groups     => [$group],
        users      => [$user],
    );
}

###############################################################################
# TEST: preserve indirect UGR/GWR/GAR
#
# User can have a *doubly-indirect* Role in an Account by virtue of being a
# member of a Group that has a Role in a Workspace in an Account.  Whew!
account_import_preserves_doubly_indirect_role: {
    pass 'TEST: Preserves UGR/GWR/GARs (doubly-indirect)';
    my $account   = create_test_account_bypassing_factory();
    my $workspace = create_test_workspace(account => $account);
    my $group     = create_test_group();
    my $user      = create_test_user();

    # Add the User to the Account through a Group-in-Workspace membership.
    $workspace->add_group(group => $group);
    $group->add_user(user => $user);

    # Export and re-import the Account.
    export_and_reimport_account(
        account    => $account,
        workspaces => [$workspace],
        groups     => [$group],
        users      => [$user],
    );
}

###############################################################################
# TEST: preserve multiple indirect UARs
#
# User can have multiple *indirect* Roles in an Account through various means.
account_import_preserves_multiple_indirect_uars: {
    pass 'TEST: Preserves multiple indirect UARs';
    my $account   = create_test_account_bypassing_factory();
    my $ws_one    = create_test_workspace(account => $account);
    my $ws_two    = create_test_workspace(account => $account);
    my $group_one = create_test_group();
    my $group_two = create_test_group();
    my $user      = create_test_user();

    # Indirect Role: User->Group->Account
    $account->add_group(group => $group_one);
    $group_one->add_user(user => $user);

    # Indirect Role: User->Workspace->Account
    $ws_one->add_user(user => $user);

    # Indirect Role: User->Group->Workspace->Account
    $ws_two->add_group(group => $group_two);
    $group_two->add_user(user => $user);

    # Export and re-import the Account.
    export_and_reimport_account(
        account    => $account,
        workspaces => [$ws_one, $ws_two],
        groups     => [$group_one, $group_two],
        users      => [$user],
    );
}

###############################################################################
# TEST: preserve multiple direct and indirect UARs
#
# User can have both a *direct* and an *indirect* Role in an Account.
account_import_preserves_direct_and_indirect_uars: {
    pass 'TEST: Preserves direct and indirect UARs';
    my $account   = create_test_account_bypassing_factory();
    my $ws_one    = create_test_workspace(account => $account);
    my $ws_two    = create_test_workspace(account => $account);
    my $group_one = create_test_group();
    my $group_two = create_test_group();
    my $user      = create_test_user();

    # Direct Role: User->Account (as his Primary Account)
    $user->primary_account( $account );

    # Indirect Role: User->Group->Account
    $account->add_group(group => $group_one);
    $group_one->add_user(user => $user);

    # Indirect Role: User->Workspace->Account
    $ws_one->add_user(user => $user);

    # Indirect Role: User->Group->Workspace->Account
    $ws_two->add_group(group => $group_two);
    $group_two->add_user(user => $user);

    # Export and re-import the Account.
    export_and_reimport_account(
        account    => $account,
        workspaces => [$ws_one, $ws_two],
        groups     => [$group_one, $group_two],
        users      => [$user],
    );
}

###############################################################################
# TEST: "system created Users" revert to regular Users on import.
account_import_system_user_roles: {
    pass 'TEST: importing of system-created user roles';
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name;
    my $user      = create_test_user(account => $account);
    my $username  = $user->username;

    sql_execute(q{UPDATE "UserMetadata" SET is_system_created = true WHERE user_id = ?}, $user->user_id);

    # Export and re-import the Account; UAR should be preserved
    stderr_is {
        export_and_reimport_account(
            account => $account,
            users   => [$user],
        );
    } "$username was system created. Importing as regular user.\n";

    $account = Socialtext::Account->new(name => $acct_name);
    $user    = Socialtext::User->new(username => $username);
    is $account->user_count(direct => 1), 1, "still got imported";
    ok !$user->is_system_created, "but is not a system user";
}

###############################################################################
# TEST: Preserve Role in Primary Account
preserve_role_in_primary_account: {
    pass 'TEST: preserve role in primary account';
    my $account   = create_test_account_bypassing_factory();
    my $acct_name = $account->name;

    my $u_member = create_test_user(account => $account);

    my $u_impersonator = create_test_user(account => $account);
    $account->assign_role_to_user(user => $u_impersonator, role => $Impersonator);

    my $u_admin = create_test_user(account => $account);
    $account->assign_role_to_user(user => $u_admin, role => $Admin);

    # Export and re-import the Account
    export_and_reimport_account(
        account => $account,
        users   => [$u_member, $u_impersonator, $u_admin],
    );

    # Double-check Roles for the Users
    $account = Socialtext::Account->new(name => $acct_name);
    isa_ok $account, 'Socialtext::Account', '... found re-imported Account';

    check_member: {
        my $found = Socialtext::User->new(username => $u_member->username);
        isa_ok $found, 'Socialtext::User', '... found re-imported Member';


        my $role = $account->role_for_user($found);
        is $role->name, $Member->name, '... ... with Member Role';
    }

    check_impersonator: {
        my $found = Socialtext::User->new(username => $u_impersonator->username);
        isa_ok $found, 'Socialtext::User', '... found re-imported Impersonator';

        my $role = $account->role_for_user($found);
        is $role->name, $Impersonator->name, '... ... with Impersonator Role';
    }

    check_admin: {
        my $found = Socialtext::User->new(username => $u_admin->username);
        isa_ok $found, 'Socialtext::User', '... found re-imported Admin';

        my $role = $account->role_for_user($found);
        is $role->name, $Admin->name, '... ... with Admin Role';
    }
}
