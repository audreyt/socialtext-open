#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 9;
use Test::Differences;
use Sys::Hostname qw(hostname);
use Socialtext::Account;

###############################################################################
# Fixtures: clean db destructive
# - Need a clean slate to start with, so we *only* have to test for the
#   default set of Accounts and the ones that we create
# - We're also destructive; we nuke the default "hostname" Account
fixtures(qw( clean db destructive ));

###############################################################################
# Specify the list of built-in Accounts, from @ST::Accounts::RequiredAccounts.
my @BUILT_IN_ACCOUNTS = qw( Socialtext Deleted Unknown );

###############################################################################
# Delete the per-hostname Account, to make result ordering easier (otherwise
# we have to take the hostname into Account).
delete_per_hostname_account: {
    my $hostname = hostname();
    my $account  = Socialtext::Account->new( name => $hostname );
    isa_ok $account, 'Socialtext::Account', 'Hostname Account';
    $account->delete();
}

###############################################################################
# TEST: All Accounts, default ordering
all_accounts_default_order: {
    my $cursor   = Socialtext::Account->All();
    my @accounts = map { $_->name } $cursor->all();
    my @expected = sort @BUILT_IN_ACCOUNTS;
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, default order'
    );
}

###############################################################################
# TEST: All Accounts, default ordering, limited
all_accounts_default_order_limited: {
    my $cursor   = Socialtext::Account->All( limit => 2 );
    my @accounts = map { $_->name } $cursor->all();
    my @expected = (sort @BUILT_IN_ACCOUNTS)[0,1];
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, default order, limited'
    );
}

###############################################################################
# TEST: All Accounts, default ordering, limit and offset
all_accounts_default_order_limit_offset: {
    my $cursor   = Socialtext::Account->All( limit => 2, offset => 1 );
    my @accounts = map { $_->name } $cursor->all();
    my @expected = (sort @BUILT_IN_ACCOUNTS)[1,2];
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, default order, limit and offset'
    );
}

###############################################################################
# TEST: All Accounts, default ordering, DESC
all_accounts_default_order_descending: {
    my $cursor   = Socialtext::Account->All( sort_order => 'DESC' );
    my @accounts = map { $_->name } $cursor->all();
    my @expected = reverse sort @BUILT_IN_ACCOUNTS;
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, default order, DESC'
    );
}

###############################################################################
# TEST: All Accounts, ordered by name
all_accounts_ordered_by_name: {
    my $cursor   = Socialtext::Account->All( order_by => 'name' );
    my @accounts = map { $_->name } $cursor->all();
    my @expected = sort @BUILT_IN_ACCOUNTS;
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, ordered by name'
    );
}

###############################################################################
# TEST: All Accounts by type, ordered by name
all_accounts_ordered_by_name: {
    my $cursor   = Socialtext::Account->All( order_by => 'name', type => 'Standard' );
    my @accounts = map { $_->name } $cursor->all();
    my @expected = sort @BUILT_IN_ACCOUNTS;
    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts by type, ordered by name'
    );
}

###############################################################################
# TEST: All Accounts, ordered by workspace_count.  Relies on workspace_count()
# returning the correct number of Workspaces (but that's tested _elsewhere_)
all_accounts_ordered_by_workspace_count: {
    # create some test Accounts, and add some Workspaces to them
    my @account_names;
    my $make_account = sub {
        my ($acct_name, $num_ws) = @_;
        my $account = create_test_account_bypassing_factory($acct_name);
        push @account_names, $acct_name;
        for (0 .. $num_ws) { create_test_workspace(account => $account) }
    };
    $make_account->( 'AAA',  3 );  # add num WS's out of order w.r.t. Acct name
    $make_account->( 'XXX', 10 );
    $make_account->( 'ZZZ',  5 );

    # get the list of All Accounts
    my $cursor   = Socialtext::Account->All( order_by => 'workspace_count' );
    my @accounts = map { $_->name } $cursor->all();

    # two-level sort.... "WS count" and then "WS name"
    my @expected =
        map  { $_->name }
        sort {
               ($a->workspace_count <=> $b->workspace_count)
            || ($a->name cmp $b->name)
        }
        map { Socialtext::Account->new(name => $_) }
        (@BUILT_IN_ACCOUNTS, @account_names);

    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, ordered by workspace_count'
    );

    # CLEANUP, so we don't pollute the next test
    map {
        eval { Socialtext::Account->new(name => $_)->delete }
    } @account_names;
}

###############################################################################
# TEST: All Accounts, ordered by user_count.  Relies on user_count() returning
# the correct number of Users (but that's tested _elsewhere_)
all_accounts_ordered_by_user_count: {
    # create some test Accounts, and add some Users to them
    my @account_names;
    my $make_new_account = sub {
        my %p       = @_;
        my $account = create_test_account_bypassing_factory($p{name});
        my $ws      = create_test_workspace(account => $account);
        my $group   = create_test_group(account => $account);
        $ws->add_group(group => $group);
        push @account_names, $account->name();

        my $users_created = 0;
        for (0 .. $p{primary}) {    # primary account
            my $user = create_test_user(account => $account);
            $users_created++;
        }
        for (0 .. $p{uwr}) {        # secondary account, as UWR
            my $user = create_test_user();
            $ws->add_user(user => $user);
            $users_created++;
        }
        for (0 .. $p{gwr}) {        # secondary account, as UGR+GWR
            my $user = create_test_user();
            $group->add_user(user => $user);
            $users_created++;
        }
    };
    $make_new_account->(name => 'AAA', primary => 10, uwr => 0, gwr =>  0);
    $make_new_account->(name => 'XXX', primary =>  0, uwr => 6, gwr => 10);
    $make_new_account->(name => 'ZZZ', primary =>  2, uwr => 1, gwr =>  1);

    # get the list of All Accounts
    my $cursor   = Socialtext::Account->All( order_by => 'user_count' );
    my @accounts = map { $_->name } $cursor->all();

    # two-level sort.... "User count" and then "WS name"
    my @expected =
        map  { $_->name }
        sort {
               ($a->user_count <=> $b->user_count)
            || ($a->name cmp $b->name)
        }
        map { Socialtext::Account->new(name => $_) }
        (@BUILT_IN_ACCOUNTS, @account_names);

    eq_or_diff(
        \@accounts, \@expected,
        'All Accounts, ordered by user_count'
    );

    # CLEANUP, so we don't pollute the next test
    map {
        eval { Socialtext::Account->new(name => $_)->delete }
    } @account_names;
}
