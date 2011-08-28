#!perl

use strict;
use warnings;
use Test::Socialtext tests => 25;
use Socialtext::CLI;
use Socialtext::Account;
use Test::Socialtext::CLIUtils qw(:all);
use Test::Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: Create User, make sure they got created.
create_user: {
    my $guard = Test::Socialtext::User->snapshot();

    expect_success(
        call_cli_argv(
            'create-user',
            '--email'    => 'test@example.com',
            '--password' => 'foobar',
        ),
        qr/\QA new user with the username "test\E\@\Qexample.com" was created.\E/,
        'create-user success message'
    );

    my $user = Socialtext::User->new( username => 'test@example.com' );
    ok $user, 'User was created via create_user';
    ok $user->password_is_correct('foobar'), 'check that given password works';
    is $user->email_address, 'test@example.com', 'email/username are the same';
    is $user->primary_account->name, Socialtext::Account->Default->name,
        'default primary account set';

    # Can only have *one* User with this e-mail at any given time
    expect_failure(
        call_cli_argv(
            'create-user',
            '--email'    => 'test@example.com',
            '--password' => 'foobar',
        ),
        qr/\QThe email address you provided, "test\E\@\Qexample.com", is already in use.\E/,
        'create-user failed with dupe email'
    );
}

###############################################################################
# TEST: Create User, into a specific Account
create_user_specific_account: {
    my $guard = Test::Socialtext::User->snapshot();

    expect_success(
        call_cli_argv(
            'create-user',
            '--email'    => 'account-test@example.com',
            '--password' => 'foobar',
            '--account'  => 'Socialtext',
        ),
        qr/\QA new user with the username "account-test\E\@\Qexample.com" was created.\E/,
        'create-user success message'
    );
    my $user = Socialtext::User->new( username => 'account-test@example.com' );
    is $user->primary_account->name, Socialtext::Account->Socialtext->name,
        'primary account set';
}

###############################################################################
# TEST: Create User with external Private ID
create_user_private_id: {
    my $guard = Test::Socialtext::User->snapshot();
    my $email = Test::Socialtext::create_unique_id() . '@ken.socialtext.net';
    my $external_id = 'abc123';
    expect_success(
        call_cli_argv(
            'create-user',
             '--email'       => $email,
             '--password'    => 'password',
             '--external-id' => $external_id,
        ),
        qr/A new user with the username "[^"]+" was created./,
        'created user with a private external id',
    );
    my $user = Socialtext::User->new(email_address => $email);
    isa_ok $user, 'Socialtext::User', 'got a user';
    is $user->private_external_id, $external_id, '... with external ID';

    # User with conflicting external private ID (ID recycled from above)
    $email = Test::Socialtext::create_unique_id() . '@ken.socialtext.net';
    expect_failure(
        call_cli_argv(
            'create-user',
            '--email'       => $email,
            '--password'    => 'password',
            '--external-id' => $external_id,
        ),
        qr/The private external id you provided \([^\)]+\) is already in use./,
        'failed to create user with a conflicting external id',
    );
}

###############################################################################
# TEST: Check for required fields
required_field_check: {
    my $guard = Test::Socialtext::User->snapshot();
    expect_failure(
        call_cli_argv(
            'create-user',
        ),
        qr/Username is a required field.+Email address is a required field.+password is required/s,
        'create-user failed with no args'
    );
}

###############################################################################
# TEST: Create user with first/middle/last names
create_user_with_names: {
    my $guard  = Test::Socialtext::User->snapshot();
    my $email  = Test::Socialtext::create_unique_id() . '@ken.socialtext.net';
    my $first  = 'Bubba';
    my $middle = 'Bo Bob';
    my $last   = 'Brain';

    expect_success(
        call_cli_argv(
            'create-user',
            '--email'       => $email,
            '--first-name'  => $first,
            '--middle-name' => $middle,
            '--last-name'   => $last,
            '--password'    => 'abc123',
        ),
        qr/A new user with the username.*was created/,
        'test User created successfully',
    );

    my $user = Socialtext::User->new(email_address => $email);
    ok $user, '... and can be found in the DB';
    is $user->first_name,  $first,  '... with correct first name';
    is $user->middle_name, $middle, '... with correct middle name';
    is $user->last_name,   $last,   '... with correct last name';
}
