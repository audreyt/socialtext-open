#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 31;
use Socialtext::CLI;
use Test::Socialtext::CLIUtils qw(expect_failure expect_success);

fixtures(qw( db ));

my $AdminRole  = Socialtext::Role->Admin();
my $MemberRole = Socialtext::Role->Member();

###############################################################################
# TEST: Add User as Account Admin when they have *no* role in Account
add_user_as_account_admin: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username = $user->username;
    my $acct_name  = $acct->name;

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--username', $username, '--account', $acct_name],
            )->add_account_admin();
        },
        qr/$username now has the role of 'admin' in the $acct_name Account/,
        'User added as Admin to Account',
    );

    ok $acct->user_has_role(user => $user, role => $AdminRole),
        '... and User has Admin Role in Acct';
}

###############################################################################
# TEST: Add User as Acct Admin when they're already a Member of the Acct
add_member_user_as_account_admin: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username = $user->username;
    my $acct_name  = $acct->name;

    $acct->add_user(user => $user);
    ok $acct->user_has_role(user => $user, role => $MemberRole),
        'User starts off as a Member of the Acct';

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--username', $username, '--account', $acct_name],
            )->add_account_admin();
        },
        qr/$username now has the role of 'admin' in the $acct_name Account/,
        'User elevated to Admin of Account',
    );

    ok $acct->user_has_role(user => $user, role => $AdminRole),
        '... and User has Admin Role in Acct';
}

###############################################################################
# TEST: Add User as Acct Admin when they're already an Admin of the Acct
add_admin_user_as_account_admin: {
    my $acct   = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username = $user->username;
    my $acct_name  = $acct->name;

    $acct->add_user(user => $user, role => $AdminRole);
    ok $acct->user_has_role(user => $user, role => $AdminRole),
        'User starts off as an Admin of the Acct';

    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => ['--username', $username, '--account', $acct_name],
            )->add_account_admin();
        },
        qr/already has the role of 'admin' in the $acct_name Account/,
        'User already has Admin Role in Account',
    );
}

###############################################################################
# TEST: Remove Acct Admin from Acct
remove_account_admin: {
    my $acct   = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username     = $user->username;
    my $display_name = $user->display_name;
    my $acct_name      = $acct->name;

    $acct->add_user(user => $user, role => $AdminRole);
    ok $acct->user_has_role(user => $user, role => $AdminRole),
        'User starts off as an Admin of the Acct';

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => ['--username', $username, '--account', $acct_name],
            )->remove_account_admin();
        },
        qr/$display_name no longer has the role of 'admin' in the $acct_name Account/,
        'User removed as Admin from Account',
    );

    ok $acct->user_has_role(user => $user, role => $MemberRole),
        '... and User was left with Member Role in Acct';
}

###############################################################################
# TEST: Remove Acct Admin from Acct when they're only a Member
remove_member_as_account_admin: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username     = $user->username;
    my $display_name = $user->display_name;
    my $acct_name    = $acct->name;

    $acct->add_user(user => $user, role => $MemberRole);
    ok $acct->user_has_role(user => $user, role => $MemberRole),
        'User starts off as an Member of the Acct';

    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [ '--username', $username, '--account', $acct_name ],
            )->remove_account_admin();
        },
        qr/$display_name does not have the role of 'admin' in the $acct_name Account/,
        'User was not an Admin; cannot remove them as an Admin',
    );

    ok $acct->user_has_role(user => $user, role => $MemberRole),
        '... and User still has Member Role in Acct';
}

###############################################################################
# TEST: Remove Acct Admin from Acct when they're not in the Acct
remove_non_member_as_account_admin: {
    my $acct = create_test_account_bypassing_factory();
    my $user = create_test_user();

    my $username     = $user->username;
    my $display_name = $user->display_name;
    my $acct_name    = $acct->name;

    ok !$acct->has_user($user),
        'User starts off not being associated with Acct';

    expect_failure(
        sub {
            Socialtext::CLI->new(
                argv => [ '--username', $username, '--account', $acct_name ],
            )->remove_account_admin();
        },
        qr/$display_name does not have the role of 'admin' in the $acct_name Account/,
        'User was not a member of Account to begin with',
    );

    ok !$acct->has_user($user), '... User still has no Role in Acct';
}

###############################################################################
# TEST: Show list of Acct Admins
show_account_admins: {
    my $acct           = create_test_account_bypassing_factory();
    my $admin_user     = create_test_user();
    my $member_user    = create_test_user();
    my $unrelated_user = create_test_user();

    my $acct_name          = $acct->name;
    my $admin_username     = $admin_user->username;
    my $member_username    = $member_user->username;
    my $unrelated_username = $unrelated_user->username;

    $acct->add_user(user => $admin_user, role => $AdminRole);
    ok $acct->user_has_role(user => $admin_user, role => $AdminRole),
        'User starts off as an Admin of the Acct';

    $acct->add_user(user => $member_user, role => $MemberRole);
    ok $acct->user_has_role(user => $member_user, role => $MemberRole),
        'User starts off as an Member of the Acct';

    ok !$acct->has_user($unrelated_user), 'User has no Role in the Acct';

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct_name ],
            )->show_account_admins();
        },
        qr/$admin_username/s,
        'Admin User is shown as an Admin of the Acct',
    );

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct_name ],
            )->show_account_admins();
        },
        qr/(?!$member_username)/s,
        'Member User is *not* shown as an Admin of the Acct',
    );

    expect_success(
        sub {
            Socialtext::CLI->new(
                argv => [ '--account', $acct_name ],
            )->show_account_admins();
        },
        qr/(?!$unrelated_username)/s,
        'Unrelated User is *not* shown as an Admin of the Acct',
    );
}
