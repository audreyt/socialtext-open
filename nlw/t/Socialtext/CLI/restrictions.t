#!perl

use strict;
use warnings;
use Test::Socialtext tests => 105;
use Socialtext::CLI;
use Test::Socialtext::CLIUtils qw(:all);
use Test::Socialtext::User;
use Email::Send::Test;

fixtures(qw( db ));

$Socialtext::EmailSender::Base::SendClass = 'Test';

###############################################################################
# TEST: Can confirm User with outstanding e-mail confirmation.
confirm_user: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation();
    ok $user->email_confirmation,  '... e-mail confirmation set';
    ok !$user->has_valid_password(), '... password is empty';

    expect_success(
        call_cli_argv(
            'confirm-user',
            '--email'    => $user->email_address,
            '--password' => 'foobar',
        ),
        qr/has been confirmed with password foobar/,
        'confirm-user success message'
    );

    # reload User and check that they were confirmed properly
    $user->reload;
    ok !$user->email_confirmation, '... e-mail confirmation was removed';
    ok $user->has_valid_password(), '... password now valid after confirmation';
}

###############################################################################
# TEST: Cannot confirm a User that has *no* outstanding e-mail confirmation
cannot_confirm_already_confirmed_user: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user();
    ok $user, 'Created test User';

    ok !$user->email_confirmation, '... has no e-mail confirmation';

    expect_failure(
        call_cli_argv(
            'confirm-user',
            '--email'    => $user->email_address,
            '--password' => 'foobar',
        ),
        qr/has already been confirmed\E/,
        'confirm-user failed with already confirmed user'
    );
}

###############################################################################
# TEST: Change the password for a User.
change_password: {
    my $guard  = Test::Socialtext::User->snapshot;
    my $user   = create_test_user();
    my $new_pw = 'valid-password';

    expect_success(
        call_cli_argv(
            'change-password',
            '--username' => $user->username,
            '--password' => $new_pw,
        ),
        qr/The password for \S+ has been changed\./,
        'change password successfully',
    );

    $user->reload;
    ok $user->password_is_correct($new_pw), 'new password is valid';
}

###############################################################################
# TEST: Changing User's password fails if password is too short.
change_password_too_short: {
    my $guard  = Test::Socialtext::User->snapshot;
    my $user   = create_test_user();

    expect_failure(
        call_cli_argv(
            'change-password',
            '--username' => $user->username,
            '--password' => 'bad',
        ),
        qr/\QPasswords must be at least 6 characters long.\E/,
        'password is too short',
    );
}

###############################################################################
# TEST: Changing User's password removes any "change password" restrictions
change_password_removes_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user();
    ok $user, 'Created test user';

    $user->create_password_change_confirmation();
    ok $user->password_change_confirmation, '... password change set';

    expect_success(
        call_cli_argv(
            'change-password',
            '--username' => $user->username,
            '--password' => 'abc123',
        ),
        qr/The password for \S+ has been changed\./,
        'change password successfully',
    );

    # reload User and check that the restriction is now gone
    $user->reload;
    ok !$user->password_change_confirmation, '... password change cleared';
}

###############################################################################
# TEST: Add an "email confirmation" restriction to a User
add_email_confirmation_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    ok !$user->email_confirmation, '... has no e-mail confirmation';
    Email::Send::Test->clear;

    expect_success(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'email_confirmation',
        ),
        qr/has been given the 'email_confirmation' restriction/,
        '... given an e-mail confirmation restriction'
    );

    ok $user->email_confirmation, '... User now has e-mail confirmation';

    my @emails = Email::Send::Test->emails();
    is @emails, 1, '... and an e-mail message was sent';
}

###############################################################################
# TEST: Add a "password change" restriction to a User
add_password_change_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    ok !$user->password_change_confirmation,
        '... has no password change restriction';
    Email::Send::Test->clear;

    expect_success(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'password_change',
        ),
        qr/has been given the 'password_change' restriction/,
        '... given a password change restriction'
    );

    ok $user->password_change_confirmation,
        '... User now has password change restriction';

    my @emails = Email::Send::Test->emails();
    is @emails, 1, '... and an e-mail message was sent';
}

###############################################################################
# TEST: Add a "requires_external_id" restriction to a User
add_requires_external_id_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    # Set an External Id into  the User record, and make sure its there
    my $extern_id = 'abc123';
    $user->update_private_external_id($extern_id);

    $user->reload;
    is $user->private_external_id, $extern_id, '... External Id set';

    # Add this restriction to the User
    expect_success(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'require_external_id',
        ),
        qr/has been given the 'require_external_id' restriction/,
        '... given a external id restriction'
    );
    $user->reload;

    ok $user->is_restricted, '... User now has some form of restriction';

    my $restriction = $user->restrictions->next;
    isa_ok $restriction, 'Socialtext::User::Restrictions::require_external_id',
        '... an External Id requirement';

    ok !$user->private_external_id, '... existing External Id was cleared';
}

###############################################################################
# TEST: Add an unknown/invalid restriction to a User
add_invalid_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    is $user->restrictions->count, 0, '... has no restrictions';
    Email::Send::Test->clear;

    expect_failure(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'invalid-restriction',
        ),
        qr/unknown restriction type, 'invalid-restriction'/,
        '... failed due to unknown restriction type'
    );

    is $user->restrictions->count, 0, '... User still has no restrictions';

    my @emails = Email::Send::Test->emails();
    is @emails, 0, '... and NO e-mail message was sent';
}

###############################################################################
# TEST: Add multiple restrictions
add_multiple_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    is $user->restrictions->count, 0, '... has no restrictions';

    expect_success(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'email_confirmation',
            '--restriction' => 'password_change',
        ),
        qr/has been given.*has been given/s,
        '... multiple restrictions added',
    );
    is $user->restrictions->count, 2, '... User has restrictions';

    my @emails = Email::Send::Test->emails();
    is @emails, 2, '... and e-mail messages were sent';
}

###############################################################################
# TEST: Add multiple restrictions aborts on unknown/invalid restriction
add_multiple_restrictions_abort_on_invalid: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user  = create_test_user;
    ok $user, 'Created test user';

    is $user->restrictions->count, 0, '... has no restrictions';

    expect_failure(
        call_cli_argv(
            'add-restriction',
            '--username'    => $user->username,
            '--restriction' => 'email_confirmation',
            '--restriction' => 'invalid-restriction',
        ),
        qr/unknown restriction type, 'invalid-restriction'/,
        '... aborted on invalid restriction',
    );
    is $user->restrictions->count, 0, '... User still has no restrictions';
}

###############################################################################
# TEST: Remove a "email confirmation" restriction (as a restriction)
remove_email_confirmation_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation();
    ok $user->email_confirmation, '... e-mail confirmation set';

    Email::Send::Test->clear;
    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'email_confirmation',
        ),
        qr/'email_confirmation' restriction has been lifted/,
        '... restriction lifted',
    );

    # reload User and check that the restriction was removed
    $user->reload;
    ok !$user->email_confirmation, '... restriction no longer set';

    my @emails = Email::Send::Test->emails();
    is @emails, 1, '... and an e-mail message was sent';
}

###############################################################################
# TEST: Remove a "password change" restriction (as a restriction)
remove_password_change_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_password_change_confirmation();
    ok $user->password_change_confirmation, '... password change set';

    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'password_change',
        ),
        qr/'password_change' restriction has been lifted/,
        '... restriction lifted',
    );

    # reload User and check that the restriction was removed
    $user->reload;
    ok !$user->password_change_confirmation, '... restriction no longer set';
}

###############################################################################
# TEST: Remove an unknown/invalid restriction
remove_unknown_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    expect_failure(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'invalid-restriction',
        ),
        qr/unknown restriction type, 'invalid-restriction'/,
        '... failed due to unknown restriction type'
    );
}

###############################################################################
# TEST: Remove known (but unset) restriction
remove_unset_restriction: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'email_confirmation',
        ),
        qr/does not have the 'email_confirmation' restriction/,
        '... reports unset restriction'
    );
}

###############################################################################
# TEST: Remove multiple restrictions
remove_multiple_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation;
    $user->create_password_change_confirmation;
    ok $user->email_confirmation, '... e-mail confirmation set';
    ok $user->password_change_confirmation, '... password change set';

    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'email_confirmation',
            '--restriction' => 'password_change',
        ),
        qr/has been lifted.*has been lifted/s,
        '... restrictions lifted'
    );

    # reload User and check that the restrictions were removed
    ok !$user->email_confirmation, '... e-mail confirmation cleared';
    ok !$user->password_change_confirmation, '... password change cleared';
}

###############################################################################
# TEST: Remove multiple restrictions aborts on unknown/invalid restriction
remove_multiple_restriction_abort_on_invalid: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation;
    $user->create_password_change_confirmation;
    ok $user->email_confirmation, '... e-mail confirmation set';
    ok $user->password_change_confirmation, '... password change set';

    expect_failure(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'email_confirmation',
            '--restriction' => 'invalid-restriction',
            '--restriction' => 'password_change',
        ),
        qr/unknown restriction type, 'invalid-restriction'/,
        '... fails on invalid restriction'
    );

    # reload User and make sure that all restrictions are still in place
    $user->reload;
    ok $user->email_confirmation, '... e-mail confirmation still set';
    ok $user->password_change_confirmation, '... password change still set';
}

###############################################################################
# TEST: Remove multiple restrictions reports unset restriction
remove_multiple_restriction_abort_on_unset: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation;
    ok $user->email_confirmation, '... e-mail confirmation set';

    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'email_confirmation',
            '--restriction' => 'password_change',
        ),
        qr/does not have the 'password_change' restriction/,
        '... reports about unset restriction'
    );

    # reload User and make sure that the other restriction got removed
    $user->reload;
    ok !$user->email_confirmation, '... e-mail confirmation removed';
}

###############################################################################
# TEST: Remove all restrictions
remove_all_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    $user->create_email_confirmation;
    $user->create_password_change_confirmation;
    ok $user->email_confirmation, '... e-mail confirmation set';
    ok $user->password_change_confirmation, '... password change set';

    expect_success(
        call_cli_argv(
            'remove-restriction',
            '--email'       => $user->email_address,
            '--restriction' => 'all',
        ),
        qr/has been lifted.*has been lifted/s,
        '... restrictions removed',
    );

    # reload User and check that the restrictions were removed
    $user->reload;
    ok !$user->email_confirmation, '... e-mail confirmation cleared';
    ok !$user->password_change_confirmation, '... password change cleared';
}

###############################################################################
# TEST: List restrictions for a User
list_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    my $user = create_test_user();
    ok $user, 'Created test User';

    # With *NO* restrictions
    expect_success(
        call_cli_argv(
            'list-restrictions',
            '--email' => $user->email_address,
        ),
        qr/No restrictions for user/,
        '... User listed with no restrictions',
    );

    # With multiple restrictions
    my $r_email    = $user->create_email_confirmation;
    my $r_password = $user->create_password_change_confirmation;

    my $expected =
        join '.*',
            map { "\Q$_\E" }
                $r_email->restriction_type,    $r_email->token,
                $r_password->restriction_type, $r_password->token;

    expect_success(
        call_cli_argv(
            'list-restrictions',
            '--email' => $user->email_address,
        ),
        qr/$expected/s,
        '... User shown to have multiple restrictions',
    );
}
