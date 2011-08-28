#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Account;
use Socialtext::Group;
use Socialtext::User;

use Test::Socialtext tests => 8;

fixtures('db');

my $class = 'Socialtext::Account::Transformer';
use_ok $class;

my $into_acct = create_test_account_bypassing_factory();
my $acct      = create_test_account_bypassing_factory();

################################################################################
no_account_name: {
    my $xform = $class->new(into_account_name => $into_acct->name);

    eval { $xform->acct2group(); };
    my $e = $@;
    like $e, qr/No account name argument passed/,
        'died, missing account_name argument';

}

################################################################################
into_acct_is_not_deleted: {
    my $xform = $class->new(
        into_account_name => Socialtext::Account->Deleted->name);

    eval { $xform->acct2group(account_name => $acct->name); };
    my $e = $@;
    like $e, qr/Cannot transform into the 'Deleted' account/,
        'died, used Deleted as the into_account';
}

################################################################################
into_account_matches_old_account: {
    my $xform = $class->new(into_account_name => $acct->name);

    eval { $xform->acct2group(account_name => $acct->name); };
    my $e = $@;
    like $e, qr/cannot be the same as into account/,
        'died, into_account_name cannot match account_name';
}

################################################################################
transform_a_system_account: {
    my $xform = $class->new(into_account_name => $into_acct->name);
    my ($name) = Socialtext::Account->RequiredAccounts();

    eval { $xform->acct2group(account_name => $name); };
    my $e = $@;
    like $e, qr/Cannot transform a system account/,
        'died, account_name cannot be a system account';
}

################################################################################
account_name_does_not_exist: {
    my $xform = $class->new(into_account_name => $into_acct->name);

    eval { $xform->acct2group(account_name => 'ENOSUCHACCOUNT'); };
    my $e = $@;
    like $e, qr/No account named 'ENOSUCHACCOUNT'/,
        'died, account_name does not exist';
}

################################################################################
default_account: {
    my $xform = $class->new(into_account_name => $into_acct->name);

    eval {
        $xform->acct2group(account_name => Socialtext::Account->Default->name);
    };
    my $e = $@;
    like $e, qr/Cannot transform the default account/,
        'died, account_name cannot be the default account';
}

################################################################################
group_collision: {
    my $xform = $class->new(into_account_name => $into_acct->name);

    # This group has the same attrs as the one we'd like to create;
    my $group = Socialtext::Group->Create({
        driver_group_name  => $acct->name,
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $into_acct->account_id,
    });

    eval { $xform->acct2group(account_name => $acct->name); };
    my $e = $@;
    like $e, qr/Group with name '.+' already exists/,
        'died, account_name collides with existing group';
}
exit;
