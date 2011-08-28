#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use Test::Socialtext tests => 26;

use_ok 'Socialtext::User::Default';

my $legacy_password =
    Socialtext::User::Default->_crypt('foodbart', 'random-salt');
my $modern_password =
    Socialtext::User::Default->_encode_password('foodbart');

for my $password ($legacy_password, $modern_password) {

    ###########################################################################
    ### TEST DATA
    ###########################################################################
    my %TEST_USER = (
        user_id       => 123,
        username      => 'test-user',
        email_address => 'test-user@example.com',
        first_name    => 'First',
        middle_name   => 'Middle',
        last_name     => 'Last',
        password      => $password,
        driver_name   => 'Default',
        display_name  => 'First Last',
    );

    ###########################################################################
    # User has a valid password.
    has_valid_password: {
        my $user = Socialtext::User::Default->new(%TEST_USER);
        isa_ok $user, 'Socialtext::User::Default';
        ok $user->has_valid_password(), 'has valid password';
    }

    ###########################################################################
    # User DOESN'T have a valid password.
    does_not_have_valid_password: {
        my $user = Socialtext::User::Default->new(%TEST_USER,
            password => '*none*');
        isa_ok $user, 'Socialtext::User::Default';
        ok !$user->has_valid_password(), 'does not have valid password';
    }

    ###########################################################################
    # Can we access the user's password?
    can_access_password: {
        my $user = Socialtext::User::Default->new(%TEST_USER);
        isa_ok $user, 'Socialtext::User::Default';
        is $user->password(), $TEST_USER{password},
            'can access users password';
    }

    ###########################################################################
    # Verify user's password?
    verify_users_password: {
        my $user = Socialtext::User::Default->new(%TEST_USER);
        isa_ok $user, 'Socialtext::User::Default';
        ok $user->password_is_correct('foodbart'), 'verify password; success';
        ok !$user->password_is_correct('bleargh!'),
            'verify password; failure';

        if ($password eq $legacy_password) {
            ok $user->password_is_correct('foodbart-EXTRA-CHARS'),
                'verify password with 8+ chars; success with _crypt()';
        }
        else {
            ok !$user->password_is_correct('foodbart-EXTRA-CHARS'),
                'verify password with 8+ chars; failure with _encode_password()';
        }

    }

    ###########################################################################
    # Convert the user record back into a hash.
    to_hash: {
        my $user = Socialtext::User::Default->new(%TEST_USER);
        isa_ok $user, 'Socialtext::User::Default';

        my $hashref = $user->to_hash();
        my @fields = qw(user_id username email_address first_name middle_name
            last_name password display_name);
        my %expected = map { $_ => $TEST_USER{$_} } @fields;
        is_deeply $hashref, \%expected,
            'converted user to hash, with right structure';
    }

}

pass 'done';
