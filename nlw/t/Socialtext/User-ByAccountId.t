#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 21;
use Test::Differences;
use Socialtext::User;

###############################################################################
# Fixtures: db
# - need a DB, but don't care what's in it.
fixtures(qw( db ));

###############################################################################
# TEST: ByAccountId includes Users with this as their Primary Account
users_with_primary_account: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
    );
    dump_roles();
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } $user ],
        'ByAccountId includes Users with access as a primary account',
    );
}

###############################################################################
# TEST: ByAccountId includes Users who have access to a WS in the Account
users_with_secondary_account: {
    my $account_one = create_test_account_bypassing_factory();
    my $user_one    = create_test_user(account => $account_one);

    my $account_two = create_test_account_bypassing_factory();
    my $user_two    = create_test_user(account => $account_two);
    my $workspace   = create_test_workspace(
        account => $account_two,
        user    => $user_two,
    );

    # add the User to the Workspace, giving them *secondary* access to this
    # Account
    $workspace->add_user(user => $user_one);

    # get the Users in the second Account; should be *both* Users
    my $results = Socialtext::User->ByAccountId(
        account_id => $account_two->account_id,
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } ($user_one, $user_two) ],
        'ByAccountId includes Users with access as a secondary account',
    );
}

###############################################################################
# TEST: ByAccountId can restrict to *ONLY* Users having this Account as their
# Primary Account.
users_only_with_primary_account: {
    my $account_one = create_test_account_bypassing_factory();
    my $user_one    = create_test_user(account => $account_one);

    my $account_two = create_test_account_bypassing_factory();
    my $user_two    = create_test_user(account => $account_two);
    my $workspace   = create_test_workspace(
        account => $account_two,
        user    => $user_two,
    );

    # add the User to the Workspace, giving them *secondary* access to this
    # Account
    $workspace->add_user(user => $user_one);

    # get the Users in the second Account; should be *both* Users
    my $results = Socialtext::User->ByAccountId(
        account_id   => $account_two->account_id,
        direct => 1,
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } $user_two ],
        'ByAccountId can restrict to only Users with this as primary account',
    );
}

###############################################################################
# User has a direct role ( eg, a User/Account Role record, or is the user's
# Primary Account ) or indirect only ( eg, Group/Account Role record )
users_with_a_direct_role: {
    my $account    = create_test_account_bypassing_factory();
    my $group      = create_test_group( account => $account );
    my $user_one   = create_test_user( account => $account );
    my $user_two   = create_test_user();
    my $user_three = create_test_user();

    $account->add_user( user => $user_two );

    $group->add_user( user => $user_three );
    ok $group->has_user( $user_three );

    # Any Role
    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
    );
    is $results->count(), 3, 'three Users have a Role';
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } ($user_one, $user_two, $user_three) ],
        '... and it is Users one, two and three'
    );

    # Direct Role only
    $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        direct     => 1,
    );
    is $results->count(), 2, 'two Users have a _direct_ Role';
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } ($user_one, $user_two) ],
        '... and it is Users one and two'
    );
}

###############################################################################
# TEST: ByAccountId by default includes hidden people
include_hidden_people: {
    SKIP: {
        eval { require Socialtext::People::Profile }
            or skip("People plugin not available", 2);

        my $account  = create_test_account_bypassing_factory();
        my $user_one = create_test_user(account => $account);
        my $user_two = create_test_user(account => $account);

        # hide one of the Users
        my $profile = Socialtext::People::Profile->GetProfile($user_one->user_id);
        $profile->is_hidden(1);
        $profile->save();
        # get the Users in the second Account; should be *both* Users
        my $results = Socialtext::User->ByAccountId(
            account_id   => $account->account_id,
        );
        is $results->count(), 2, 'ByAccountId includes hidden people by default';
        eq_or_diff(
            [ map { $_->username } $results->all ],
            [ map { $_->username } ($user_one, $user_two) ],
            '... and its the Users/order we expected',
        );
    }
}

###############################################################################
# TEST: ByAccountId can exclude hidden people.
exclude_hidden_people: {
    SKIP: {
        eval { require Socialtext::People::Profile }
            or skip("People plugin not available", 2);

        my $account      = create_test_account_bypassing_factory();
        my $user_hidden  = create_test_user(account => $account);
        my $user_visible = create_test_user(account => $account);

        # hide one of the Users
        my $profile = Socialtext::People::Profile->GetProfile(
            $user_hidden->user_id
        );
        $profile->is_hidden(1);
        $profile->save();

        # get the Users in the second Account; should be *both* Users
        my $results = Socialtext::User->ByAccountId(
            account_id            => $account->account_id,
            exclude_hidden_people => 1,
        );
        is $results->count(), 1, 'ByAccountId can exclude hidden people';
        eq_or_diff(
            [ map { $_->username } $results->all ],
            [ map { $_->username } ($user_visible) ],
            '... and its the User we expected',
        );
    }
}

###############################################################################
# TEST: ByAccountId can limit the number of results
limit_number_of_results: {
    my $account = create_test_account_bypassing_factory();
    my $user_one = create_test_user(account => $account);
    my $user_two = create_test_user(account => $account);

    # LIMIT 1, OFFSET 0 (first User)
    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        limit      => 1,
    );
    is $results->count(), 1, 'ByAccountId can limit number of results';
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } ($user_one) ],
        '... and its the User we expect',
    );

    # LIMIT 1, OFFSET 1 (second User)
    $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        limit      => 1,
        offset     => 1,
    );
    is $results->count(), 1, 'ByAccountId can offset results';
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } ($user_two) ],
        '... and its the User we expect',
    );
}

###############################################################################
# TEST: ByAccountId, ordered by "username"
order_by_username: {
    my $account = create_test_account_bypassing_factory();
    my $user_one = create_test_user(account => $account);
    my $user_two = create_test_user(account => $account);

    my @sorted =
        sort { $a->username cmp $b->username }
        ($user_one, $user_two);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        order_by => 'username',
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } @sorted ],
        'ByAccountId can order by "username"',
    );
}

###############################################################################
# TEST: ByAccountId, ordered by "username", REVERSE order
order_by_username_desc: {
    my $account = create_test_account_bypassing_factory();
    my $user_one = create_test_user(account => $account);
    my $user_two = create_test_user(account => $account);

    my @sorted =
        reverse
        sort { $a->username cmp $b->username }
        ($user_one, $user_two);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        order_by   => 'username',
        sort_order => 'DESC',
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } @sorted ],
        'ByAccountId can order by "username", in DESCending order',
    );
}

###############################################################################
# TEST: ByAccountId, ordered by "creation_datetime" (which is *BACKWARDS*, so
# that newer Users go to the top)
order_by_creation_datetime: {
    my $account  = create_test_account_bypassing_factory();
    my $user_one = create_test_user(account => $account);
    my $user_two = create_test_user(account => $account);

    my @sorted =
        reverse
        sort { $a->creation_datetime cmp $b->creation_datetime }
        ($user_one, $user_two);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        order_by   => 'creation_datetime',
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } @sorted ],
        'ByAccountId can order by "creation_datetime" (DESCending)',
    );
}

###############################################################################
# TEST: ByAccountId, ordered by "creator"
ordered_by_creator: {
    my $creator_one = create_test_user();
    my $creator_two = create_test_user();

    # create some Users, but in reverse order (so we know if they get ordered
    # right by creator id)
    my $account  = create_test_account_bypassing_factory();
    my $user_two = create_test_user(
        account            => $account,
        created_by_user_id => $creator_two->user_id,
    );
    my $user_one = create_test_user(
        account            => $account,
        created_by_user_id => $creator_one->user_id,
    );

    my @sorted =
        sort { $a->creator->username cmp $b->creator->username }
        ($user_one, $user_two);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account->account_id,
        order_by   => 'creator',
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } @sorted ],
        'ByAccountId can order by "creator"',
    );
}

###############################################################################
# TEST: ByAccountId, ordered by "primary_account"
order_by_primary_account: {
    my $account_one = create_test_account_bypassing_factory();
    my $account_two = create_test_account_bypassing_factory();

    # create Users in reverse order (to verify sorting by Account, not their
    # Usernames)

    # ... this User has "account one" as a primary account
    my $user_two  = create_test_user(account      => $account_one);

    # ... this User has "account one" as a secondary account
    my $user_one  = create_test_user(account      => $account_two);
    my $workspace = create_test_workspace(account => $account_one);
    $workspace->add_user(user => $user_one);

    my @sorted =
        sort { $a->primary_account->name cmp $b->primary_account->name }
        ($user_one, $user_two);

    my $results = Socialtext::User->ByAccountId(
        account_id => $account_one->account_id,
        order_by   => 'primary_account',
    );
    eq_or_diff(
        [ map { $_->username } $results->all ],
        [ map { $_->username } @sorted ],
        'ByAccountId can order by "primary_account"',
    );
}
