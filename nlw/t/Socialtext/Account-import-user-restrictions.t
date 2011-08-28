#!/usr/bin/env perl

use strict;
use warnings;
use Test::Socialtext tests => 13;
use Test::Socialtext::Account qw(export_and_reimport_account);

fixtures(qw( db ));

###############################################################################
# TEST: Account export/import preserved User Restrictions
user_restrictions_preserved: {
    my $account = create_test_account_bypassing_factory();
    my $user    = create_test_user(account => $account);

    $user->add_restriction('email_confirmation');
    $user->add_restriction('password_change');

    # Export and re-import the Account; User Restrictions should be preserved
    export_and_reimport_account(
        account => $account,
        users   => [$user],
    );

    my $imported = Socialtext::User->new(username => $user->username);
    ok $imported, '... User found after import';
    ok $imported->is_restricted, '... ... is restricted';
    is $imported->restrictions->all, 2, '... ... with both restrictions';
}
