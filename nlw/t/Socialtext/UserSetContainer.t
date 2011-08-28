#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 35;
use Test::More;
use Test::Socialtext::Fatal;
BEGIN { 
    use_ok 'Socialtext::UserSet', qw/:const/;
    use_ok 'Socialtext::UserSetContainer';
}
fixtures('db');

my $user = create_test_user();
my $uid = $user->user_id;
my $uname = $user->username;
my $admin = Socialtext::Role->Admin;
my $member = Socialtext::Role->Member;
my $default_acct = Socialtext::Account->Default;
ok($default_acct->has_user($user), 'account has the user');
is($default_acct->role_for_user($user)->role_id,
    $member->role_id, 'user is a member in acct');

my $grp = create_test_group();
my $gid = $grp->group_id;
my $gname = $grp->driver_group_name;
ok($default_acct->has_group($grp), 'account has the group');
is($default_acct->role_for_group($grp)->role_id,
    $member->role_id, 'group is a member in acct');

my $test_ws = create_test_workspace();
ok($default_acct->user_set->has_role(
        $test_ws->user_set_id,
        $default_acct->user_set_id,
        Socialtext::Role->Member->role_id,
    ), 'account has the wksp');

{
    package Container;
    use Moose;
    has 'user_set_id' => (is => 'rw', isa => 'Int');
    sub impersonation_ok {return 1};
    with 'Socialtext::UserSetContainer';
}

my $c = Container->new(user_set_id => ACCT_OFFSET + 1_000_000);
ok $c;
my $cid = $c->user_set_id;
END { 
    diag "CLEANUP: remove anonymous user-set";
    # ensure that this set doesn't contaminate the database
    eval { $c->user_set->remove_set($cid) };
}

user_logging: {
    clear_log();
    my $actor = create_test_badmin();
    my $aid = $actor->user_id;
    my $aname = $actor->username;
    my $qr = qr/
        user:\Q$uname($uid)\E,
        user-set:\($cid\),
        actor:\Q$aname($aid)\E,
        \[.+?\]
    /x;

    $c->add_role(object => $user, role => $admin, actor => $actor);
    logged_like info => qr/^ASSIGN,USER_ROLE,role:admin,$qr$/;

    $c->assign_role(object => $user, role => $member, actor => $actor);
    logged_like info => qr/^CHANGE,USER_ROLE,role:member,$qr$/;

    my $rm = $c->remove_role(object => $user, actor => $actor);
    logged_like info => qr/^REMOVE,USER_ROLE,role:member,$qr$/;
    is $rm->role_id, $member->role_id;
}

group_logging: {
    clear_log();
    my $actor = create_test_badmin();
    my $aid = $actor->user_id;
    my $aname = $actor->username;
    my $qr = qr/
        group:\Q$gname($gid)\E,
        user-set:\($cid\),
        actor:\Q$aname($aid)\E,
        \[.+?\]
    /x;

    $c->add_role(object => $grp, role => $member, actor => $actor);
    logged_like info => qr/^ASSIGN,GROUP_ROLE,role:member,$qr$/;

    $c->assign_role(object => $grp, role => $admin, actor => $actor);
    logged_like info => qr/^CHANGE,GROUP_ROLE,role:admin,$qr$/;

    my $rm = $c->remove_role(object => $grp, actor => $actor);
    logged_like info => qr/^REMOVE,GROUP_ROLE,role:admin,$qr$/;
    is $rm->role_id, $admin->role_id;
}

user_group_logging: {
    clear_log();
    my $actor = create_test_badmin();
    my $aid = $actor->user_id;
    my $aname = $actor->username;
    my $qr = qr/
        user:\Q$uname($uid)\E,
        group:\Q$gname($gid)\E,
        actor:\Q$aname($aid)\E,
        \[.+?\]
    /x;

    $grp->add_role(object => $user, role => $member, actor => $actor);
    logged_like info => qr/^ASSIGN,USER_ROLE,role:member,$qr$/;

    $grp->assign_role(object => $user, role => $admin, actor => $actor);
    logged_like info => qr/^CHANGE,USER_ROLE,role:admin,$qr$/;

    my $rm = $grp->remove_role(object => $user, actor => $actor);
    logged_like info => qr/^REMOVE,USER_ROLE,role:admin,$qr$/;
    is $rm->role_id, $admin->role_id;
}

workspace_logging: {
    clear_log();
    my $actor = create_test_badmin();
    my $aid = $actor->user_id;
    my $aname = $actor->username;
    my $ws = create_test_workspace();
    my $wname = $ws->name;
    my $ws_id = $ws->workspace_id;

    my $qr = qr/
        user:\Q$uname($uid)\E,
        workspace:\Q$wname($ws_id)\E,
        actor:\Q$aname($aid)\E,
        \[.+?\]
    /x;

    $ws->add_role(object => $user, role => $member, actor => $actor);
    logged_like info => qr/^ASSIGN,USER_ROLE,role:member,$qr$/;

    $ws->assign_role(object => $user, role => $admin, actor => $actor);
    logged_like info => qr/^CHANGE,USER_ROLE,role:admin,$qr$/;

    my $rm = $ws->remove_role(object => $user, actor => $actor);
    logged_like info => qr/^REMOVE,USER_ROLE,role:admin,$qr$/;
    is $rm->role_id, $admin->role_id;
}

account_logging: {
    clear_log();
    my $actor = create_test_badmin();
    my $aid = $actor->user_id;
    my $aname = $actor->username;
    my $acct = create_test_account_bypassing_factory();
    my $acctname = $acct->name;
    my $acctid = $acct->account_id;

    my $qr = qr/
        user:\Q$uname($uid)\E,
        account:\Q$acctname($acctid)\E,
        actor:\Q$aname($aid)\E,
        \[.+?\]
    /x;

    $acct->add_role(object => $user, role => $member, actor => $actor);
    logged_like info => qr/^ASSIGN,USER_ROLE,role:member,$qr$/;

    $acct->assign_role(object => $user, role => $admin, actor => $actor);
    logged_like info => qr/^CHANGE,USER_ROLE,role:admin,$qr$/;

    my $rm = $acct->remove_role(object => $user, actor => $actor);
    logged_like info => qr/^REMOVE,USER_ROLE,role:admin,$qr$/;
    is $rm->role_id, $admin->role_id;
}

system_created_no_roles: {
    my $acct = create_test_account_bypassing_factory();
    my $actor = create_test_badmin(account => $acct);
    my $a_sys_user = create_test_user(is_system_created => 1, account => $acct);
    ok $a_sys_user, 'created a system user';

    ok exception {
        $c->add_user(actor => $actor, user => $a_sys_user);
    }, "can't add system-created users";

    ok exception {
        $c->assign_user(actor => $actor, user => $a_sys_user);
    }, "can't add system-created users";

    ok !exception {
        $c->user_set->add_object_role($a_sys_user, $member->role_id);
    }, 'super low-level interface is OK';
    ok $c->has_user($a_sys_user), 'added via super-low-level interface';

    ok !exception {
        $c->remove_user(actor => $actor, user => $a_sys_user);
    }, "can remove them though (if they did get added somehow)";
    ok !$c->has_user($a_sys_user), 'removed via high-level interface';
}
