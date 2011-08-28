#!perl

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:all);
use Test::Socialtext tests => 10;
use Test::Socialtext::User;
use Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: "Guest" is never an authenticated User
guest_is_not_authenticated: {
    my $user = Socialtext::User->Guest;
    ok !$user->is_authenticated, 'Guest User cannot be authenticated';
}

###############################################################################
# TEST: User's must have a valid password in order to become authenticated
authen_requires_password: {
    my $user = create_test_user();
    $user->update_store(
        password => '*none*',
        no_crypt => 1,
    );

    clear_log;
    ok !$user->is_authenticated, 'User w/invalid password cannot be authenticated';
    logged_like 'info', qr/has invalid password/, '... because of invalid password';
}

###############################################################################
# TEST: User's with outstanding "email confirmation"s are not authenticated
email_confirmation: {
    my $user = create_test_user();
    $user->update_store(password => 'a-valid-password');
    $user->create_email_confirmation;

    clear_log;
    ok !$user->is_authenticated, 'User w/email confirmation cannot be authenticated';
    logged_like 'info', qr/has outstanding 'email_confirmation'/, '... because of email confirmation';
}

###############################################################################
# TEST: User's with outstanding "password change"s are not authenticated
password_change: {
    my $user = create_test_user();
    $user->update_store(password => 'a-valid-password');
    $user->create_password_change_confirmation;

    clear_log;
    ok !$user->is_authenticated, 'User w/password change confirmation cannot be authenticated';
    logged_like 'info', qr/has outstanding 'password_change'/, '... because of password change confirmation';
}

###############################################################################
# TEST: Deactivated User's are not authenticated
deactivated_user: {
    my $user = create_test_user();
    $user->deactivate;

    clear_log;
    ok !$user->is_authenticated, 'Deactivated User cannot be authenticated';
    logged_like 'info', qr/deactivated/, '... because they have been deactivated';
}

###############################################################################
# TEST: A User in good standing, *is* authenticated.
happy_day: {
    my $user = create_test_user();
    $user->update_store(password => 'a-valid-password');
    ok $user->is_authenticated, 'Clean/valid User can be authenticated';
}
