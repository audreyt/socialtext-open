#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 74;
use Test::Socialtext::Fatal;
use Socialtext::SQL qw/sql_txn/;
BEGIN {
    use_ok 'Socialtext::Group';
    use_ok 'Socialtext::Workspace';
    use_ok 'Socialtext::Account';
    use_ok 'Socialtext::User';
    use_ok 'Socialtext::UserSet';
}

fixtures(qw(db));

my $member = Socialtext::Role->new(name => 'member')->role_id;
my $admin = Socialtext::Role->new(name => 'admin')->role_id;

my $usr = create_test_user();

api_for_group: {
    check_api_for_container(create_test_group());
    check_api_for_container(create_test_account_bypassing_factory());
    check_api_for_container(create_test_workspace());
}

Bad_cases: {
    Add_user_to_user: {
        my $usr2 = create_test_user();
        my $uset = Socialtext::UserSet->new;

        my $user_id1 = $usr->user_id;
        my $user_id2 = $usr2->user_id;
        like exception {
            $uset->add_role($user_id1, $user_id2, $member);
        }, qr/can't add things to users/, "cannot add user to a user";
        like exception {
            $uset->remove_role($user_id1, $user_id2);
        }, qr/edge $user_id1,$user_id2/, "cannot remove user from a user";
        like exception {
            $uset->update_role($user_id1, $user_id2, $member);
        }, qr/can't add things to users/, "cannot update user to a user";
    }

    Add_workspace_to_workspace: {
        my $wksp1 = create_test_workspace();
        my $wksp2 = create_test_workspace();

        my $error = qr/Workspace user_sets cannot/;
        like exception {
            $wksp1->add_role(
                actor => Socialtext::User->SystemUser,
                object => $wksp2,
                role => $member,
            );
        }, $error, "cannot add wksp to a wksp";
        like exception {
            $wksp1->assign_role(
                actor => Socialtext::User->SystemUser,
                object => $wksp2,
                role => $member,
            );
        }, $error, "cannot remove wksp from a wksp";
        like exception {
            $wksp1->remove_role(
                actor => Socialtext::User->SystemUser,
                object => $wksp2,
            );
        }, $error, "cannot update wksp to a wksp";
    }

    Add_account_to_account: {
        my $acct1 = create_test_account_bypassing_factory();
        my $acct2 = create_test_account_bypassing_factory();

        my $error = qr/Account user_sets cannot/;
        like exception {
            $acct1->add_role(
                actor => Socialtext::User->SystemUser,
                object => $acct2,
                role => $member,
            );
        }, $error, "cannot add acct to a acct";
        like exception {
            $acct1->assign_role(
                actor => Socialtext::User->SystemUser,
                object => $acct2,
                role => $member,
            );
        }, $error, "cannot remove acct from a acct";
    }

    Add_group_to_group: {
        my $grp1 = create_test_group();
        my $grp2 = create_test_group();

        ok !exception {
            $grp1->add_role(
                actor => Socialtext::User->SystemUser,
                object => $grp2,
                role => $member,
            );
        }, "can add grp to a grp";
        ok !exception {
            $grp1->assign_role(
                actor => Socialtext::User->SystemUser,
                object => $grp2,
                role => $member,
            );
        }, "can remove grp from a grp";
        ok !exception {
            $grp1->remove_role(
                actor => Socialtext::User->SystemUser,
                object => $grp2,
            );
        }, "can update grp to a grp";
    }

    Add_system_created_user_to_anything: {
        my $user  = create_test_user(is_system_created => 1);
        my $acct  = create_test_account_bypassing_factory();
        my $wksp  = create_test_workspace();
        my $group = create_test_group();

        my $actor = Socialtext::User->SystemUser();
        my $err   = qr/Cannot give a role to a system-created user/;

        for my $ctr ($acct, $wksp, $group) {
            like exception {
                $ctr->add_role(
                    object=>$user, actor=>$actor, user=>$user, role=>$member)
            }, $err, "cannot add a system created user";
            like exception {
                $ctr->add_role(
                    object=>$user, actor=>$actor, user=>$user, role=>$member)
            }, $err, "cannot add a system created user";
        }
    }
}

nested_txn: {
    my $grp = create_test_group();
    my $user1 = create_test_user();
    my $user2 = create_test_user();
    sql_txn {
        ok !exception { $grp->add_user(user => $user1) },
            'added first user in txn';
        ok !exception { $grp->add_user(user => $user2) },
            'added second user in txn';
    };

    ok $grp->has_user($user1);
    ok $grp->has_user($user2);
}


sub check_api_for_container {
    my $cont = shift;
    ok $cont, "got a container";
    ok $cont->user_set_id, "has a user_set_id";
    my $uset = $cont->user_set;
    is $uset->owner_id, $cont->user_set_id, "same set id";
    is $uset->owner, $cont, "owner assigned";

    ok !exception { $uset->add_object_role($usr, $member) },
        "added user to the container";

    ok  $uset->connected($usr->user_id,     $cont->user_set_id),
        "user is in the container";
    ok !$uset->connected($cont->user_set_id, $usr->user_id),
        "doesn't mean the container is in the user";

    ok $uset->has_role($usr->user_id, $cont->user_set_id, $member);
    ok $uset->has_direct_role($usr->user_id, $cont->user_set_id, $member);

    ok !exception { $uset->update_object_role($usr, $admin) }, "role updated";
    ok !$uset->has_role($usr->user_id, $cont->user_set_id, $member);
    ok  $uset->has_role($usr->user_id, $cont->user_set_id, $admin);

    ok !exception { $uset->remove_object_role($usr) }, "role updated";
    ok !$uset->has_role($usr->user_id, $cont->user_set_id, $member);
    ok !$uset->has_role($usr->user_id, $cont->user_set_id, $admin);
    ok !$uset->connected($usr->user_id, $cont->user_set_id);
}
