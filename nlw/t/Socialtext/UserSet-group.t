#!/usr/bin/env perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::Socialtext tests => 9;
use Test::Socialtext::Fatal;
use Socialtext::SQL qw/get_dbh/;
BEGIN {
    use_ok 'Socialtext::UserSet';
    use_ok 'Socialtext::Group';
    use_ok 'Socialtext::User';
}

fixtures(qw(db));

my $member = Socialtext::Role->new(name => 'member')->role_id;

my $acct = create_test_account_bypassing_factory();
my $usr = create_test_user();
my $grp = create_test_group(account => $acct);
ok $grp, "got a group";
ok $grp->user_set_id, "has a user_set_id";

user_in_group: {
    my $uset = Socialtext::UserSet->new();
    ok !exception { $uset->add_role($usr->user_id => $grp->user_set_id, $member); }, "added role";

    ok $uset->connected($usr->user_id => $grp->user_set_id), "user is a member";

    ok get_dbh()->do(q{DELETE FROM groups WHERE group_id = ?},{},$grp->group_id), "cause trigger to fire";

    ok !$uset->connected($usr->user_id => $grp->user_set_id), "user no longer a member";
}
