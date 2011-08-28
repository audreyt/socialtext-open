#!/usr/bin/env perl
# @COPYRIGHT@

# This test was created to aid in refactoring the 'account_user' view into a
# materialized view, but the mat-view turned out to be too slow.  It should
# capture the business logic of "if a user's in an workspace, they're also in
# that workspace's account".

use warnings;
use strict;

use Test::Socialtext tests => 27;
use Test::Differences;
use Socialtext::SQL qw/get_dbh/;
use Socialtext::User;
use Socialtext::UserSet qw/:const/;
use Socialtext::Account;
use Socialtext::Workspace;

fixtures( 'db' );

my($user, $user_id, $user2, $user2_id);
my($ws, $ws_id);
my($default, $default_id);
my($acct, $acct_id, $acct2, $acct2_id);

sub membership_is ($$);

setup: {
    $user = Socialtext::User->create(
        username => "user $^T",
        email_address => "user$^T\@ken.socialtext.net",
        first_name => "User",
        last_name => "$^T",
    );
    ok $user;
    $user_id = $user->user_id;
    ok $user_id;

    $user2 = Socialtext::User->create(
        username => "user2 $^T",
        email_address => "user2$^T\@ken.socialtext.net",
        first_name => "User2",
        last_name => "$^T",
    );
    ok $user2;
    $user2_id = $user2->user_id;
    ok $user2_id;

    $acct = Socialtext::Account->create(
        name => "Account $^T"
    );
    ok $acct;
    $acct_id = $acct->account_id;
    ok $acct_id;

    $acct2 = Socialtext::Account->create(
        name => "Account2 $^T"
    );
    ok $acct2;
    $acct2_id = $acct2->account_id;
    ok $acct2_id;

    $default = Socialtext::Account->Default();
    ok $default;
    $default_id = $default->account_id;
    ok $default_id;

    $ws = Socialtext::Workspace->create(
        skip_default_pages => 1,
        name => "ws_$^T",
        title => "Workspace $^T",
        account_id => $acct_id,
    );
    ok $ws;
    $ws_id = $ws->workspace_id;
    ok $ws_id;
}

baseline: {
    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
    ], 'baseline membership is default account';
}

workspace_membership: {
    $ws->add_user(user => $user);
    membership_is [
        [$default_id, $user_id ],
        [$acct_id,    $user_id ],
        [$default_id, $user2_id],
    ], 'adding a user to a workspace adds an implicit account membership';

    my $role = Socialtext::Role->new(name => 'impersonator');
    $ws->assign_role_to_user(user => $user, role => $role);
    membership_is [
        [$default_id, $user_id ],
        [$acct_id,    $user_id ],
        [$default_id, $user2_id],
    ], 'changing roles maintains the membership';

    $ws->remove_user(user => $user);
    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
    ], 'removing a user to a workspace removes the implicit membership';
}

workspace_changes_account: {
    $ws->add_user(user => $user2);
    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
        [$acct_id,    $user2_id],
    ], 'adding a user to a workspace adds an implicit account membership';

    my $old_ws = $ws;

    change_workspace_account($ws,$acct2);

    $ws = Socialtext::Workspace->new(workspace_id => $ws_id);
    ok $ws;
    is $ws->account_id, $acct2_id;

    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
        [$acct2_id,   $user2_id],
    ], 'changing the workspace\'s account changes the user\'s membership';

    $ws->remove_user(user => $user2);
    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
    ], 'removing a user to a workspace removes the implicit account membership';
}

primary_account_changes_memberhip: {
    $ws->add_user(user => $user2);
    membership_is [
        [$default_id, $user_id ],
        [$default_id, $user2_id],
        [$acct2_id,   $user2_id],
    ], 'adding a user to a workspace adds an account membership';

    $user2->primary_account($acct);
    membership_is [
        [$default_id,  $user_id ],
        [$default_id,  $user2_id],
        [$acct_id,     $user2_id],
        [$acct2_id,    $user2_id],
    ], 'changing the primary account changes the account membership';

    $user->primary_account($acct2);
    $user2->primary_account($acct2);
    membership_is [
        [$default_id, $user_id ],
        [$acct2_id,   $user_id ],
        [$default_id, $user2_id],
        [$acct_id,    $user2_id],
        [$acct2_id,   $user2_id],
    ], 'change both users primary account';
}

cleanup: {
    # Reset Primary Accounts
    $user->primary_account($acct);
    $user2->primary_account($acct);

    # Remove unneeded explicit account roles
    $default->remove_user( user => $user );
    $acct2->remove_user( user => $user );
    $default->remove_user( user => $user2 );
    $acct2->remove_user( user => $user2 );

    # Sanity check going forward
    membership_is [
        [ $acct_id,  $user_id  ],
        [ $acct_id,  $user2_id ],
        [ $acct2_id, $user2_id ],
    ], 'cleanup success, users maintain implicit account roles via workspace';
}

deleting_workspace_removes_membership: {
    $ws->delete();
    $ws = undef;

    membership_is [
        [$acct_id,  $user_id ],
        [$acct_id,  $user2_id],
    ], 'deleting workspace removes implicit account membership';
}

deleting_account_removes_membership: {
    $acct->delete();
    $acct = undef;
    membership_is [], 'deleting account removes account membership';
}

sub change_workspace_account {
    my ($w, $a) = @_;
    $ws->update( account_id => $a->account_id );
}

sub membership_is {
    my $expected = shift;
    my $name = shift;

    local $Test::Builder::Level = ($Test::Builder::Level||0) + 1;

    my $dbh = get_dbh;

    my $membership_sth = $dbh->prepare(q{
        SELECT into_set_id - }.PG_ACCT_OFFSET.q{ as account_id, from_set_id AS user_id
          FROM user_set_path
         WHERE into_set_id }.PG_ACCT_FILTER.q{
           AND from_set_id IN (?,?)
         GROUP BY user_id, account_id
         ORDER BY user_id, account_id
    });
    $membership_sth->execute($user_id, $user2_id)
        || die "execute failed: " . $membership_sth->errstr . "\n";
    my $got = $membership_sth->fetchall_arrayref;
    use Data::Dumper;
    eq_or_diff $got, $expected, $name
        or warn Dumper($got);
}

