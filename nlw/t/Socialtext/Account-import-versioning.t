#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 36;
use Test::Socialtext::Account qw/export_and_reimport_account/;

fixtures(qw( db ));

###############################################################################
# TEST: Unversioned export
unversioned: {
    my $account = create_test_account_bypassing_factory();
    my $results = export_and_reimport_account(
        return_output => 1,
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
        mangle  => sub {
            my $acct_data = shift;
            delete $acct_data->{version};
        }
    );
    like $results, qr/account imported/, '... import ok when unversioned';
}

###############################################################################
# TEST: Export and re-import at same version level.
version_match: {
    my $account = create_test_account_bypassing_factory();
    my $results = export_and_reimport_account(
        return_output => 1,
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
    );
    like $results, qr/account imported/, '... import ok at same version';
}

###############################################################################
# TEST: Export w/lower version number; imports ok.
version_lower: {
    my $account = create_test_account_bypassing_factory();
    my $results = export_and_reimport_account(
        return_output => 1,
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
        mangle  => sub {
            my $acct_data = shift;
            $acct_data->{version}--;
        },
    );
    like $results, qr/account imported/, '... import ok at lower version';
}

###############################################################################
# TEST: Export w/higher version number; fails.
version_higher: {
    my $account = create_test_account_bypassing_factory();
    my $results = export_and_reimport_account(
        return_output => 1,
        account => $account,
        flush   => sub {
            Test::Socialtext::Account->delete_recklessly($account);
        },
        mangle  => sub {
            my $acct_data = shift;
            $acct_data->{version}++;
        },
    );
    like $results, qr/Cannot import an Account with a version greater/,
        '... import FAILED at higher version';
}

