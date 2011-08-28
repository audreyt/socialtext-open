#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 29;
use Test::Socialtext::User;
use Socialtext::User;

fixtures( 'db' );
use_ok 'Socialtext::User::Default::Factory';

###############################################################################
### TEST DATA
###############################################################################
my %TEST_DATA = (
    username        => 'foobar',
    email_address   => 'devnull@socialtext.net',
    first_name      => 'Test',
    last_name       => 'User',
    password        => 'my-password',
);

###############################################################################
# Create user: all fields present
create_user_all_fields_present: {
    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%TEST_DATA) };
    isa_ok $user, 'Socialtext::User';
}

###############################################################################
# Create user: "username" is a required field
required_field_username: {
    my %data = %TEST_DATA;
    delete $data{username};

    my $user = eval { Socialtext::User->create(%data) };
    like $@, qr/username is a required field/i, 'required field: username';
}

###############################################################################
# Create user: "email_address" is a required field
required_field_email_address: {
    my %data = %TEST_DATA;
    delete $data{email_address};

    my $user = eval { Socialtext::User->create(%data) };
    like $@, qr/email.* is a required field/i, 'required field: email_address';
}

###############################################################################
# Create user: "password" is optional
optional_field_password: {
    my %data = %TEST_DATA;
    delete $data{password};

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
}

###############################################################################
# Create user: "password" is a required field (require_password=>1)
required_field_password: {
    my %data = %TEST_DATA;
    delete $data{password};
    $data{require_password} = 1;

    my $user = eval { Socialtext::User->create(%data) };
    like $@, qr/password is required/, 'required field: password';
}

###############################################################################
# Cleanup: "username" is trimmed
cleanup_username_trim: {
    my %data = %TEST_DATA;
    $data{username} = "   " . $data{username} . "    ";

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    is $user->username, $TEST_DATA{username}, 'cleanup: "username" is trimmed';
}

###############################################################################
# Cleanup: "username" is converted to lower-case
cleanup_username_lc: {
    my %data = %TEST_DATA;
    $data{username} = uc($data{username});

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    is $user->username, $TEST_DATA{username}, 'cleanup: "username" is lower-cased';
}

###############################################################################
# Cleanup: "email_address" is trimmed
cleanup_email_address_trim: {
    my %data = %TEST_DATA;
    $data{email_address} = "   " . $data{email_address} . "    ";

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    is $user->email_address, $TEST_DATA{email_address}, 'cleanup: "email_address" is trimmed';
}

###############################################################################
# Cleanup: "email_address" is converted to lower-case
cleanup_email_address_lc: {
    my %data = %TEST_DATA;
    $data{email_address} = uc($data{email_address});

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    is $user->email_address, $TEST_DATA{email_address}, 'cleanup: "email_address" is lower-cased';
}

###############################################################################
# Cleanup: password is encrypted by default
cleanup_password_encrypted: {
    my %data = %TEST_DATA;

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    isnt $user->password, $TEST_DATA{password}, 'cleanup: "password" is encrypted';
}

###############################################################################
# Cleanup: password encryption can be disabled
cleanup_password_disable_encryption: {
    my %data = %TEST_DATA;
    $data{no_crypt} = 1;

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
    is $user->password, $TEST_DATA{password}, 'cleanup: "password" encryption can be disabled';
}

###############################################################################
# Constraint: "email_address" must be a valid e-mail address
constraint_email_address_valie: {
    my %data = %TEST_DATA;
    $data{email_address} = 'this-isnt-a-valid-email-address';

    my $user = eval { Socialtext::User->create(%data) };
    like $@, qr/not a valid email/, 'constraint: "email_address" must be a valid e-mail address';
}

###############################################################################
# Constraint: "password" must be more than 6 chars in length
constraint_password_length: {
    my %data = %TEST_DATA;
    $data{password} = '12345';

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    like $@, qr/must be at least/, 'constraint: "password" too short';

    $data{password} = '123456';
    $user = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';
}

###############################################################################
# Constraint: "username" must be unique
constraint_username_unique: {
    my %data = %TEST_DATA;

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';

    $data{email_address} = 'foo@bar.com';
    my $another = eval { Socialtext::User->create(%data) };
    like $@, qr/username.*already in use/, 'constraint: "username" must be unique';
}

###############################################################################
# Constraint: "email_address" must be unique
constraint_email_address_unique: {
    my %data = %TEST_DATA;

    my $guard = Test::Socialtext::User->snapshot();
    my $user  = eval { Socialtext::User->create(%data) };
    isa_ok $user, 'Socialtext::User';

    $data{username} = 'Another Test User';
    my $another = eval { Socialtext::User->create(%data) };
    like $@, qr/email.*already in use/, 'constraint: "email_address" must be unique';
}

###############################################################################
# Constraint: can't update the "username" for a system-user
constraint_cant_update_system_username: {
    my $user = Socialtext::User->new(username => 'system-user');
    isa_ok $user, 'Socialtext::User';

    eval { $user->update_store(username => 'foobar') };
    like $@, qr/cannot change/, 'constraint: cannot update "username" for system user';
}

###############################################################################
# Constraint: can't update the "email_address" for a system-user
constraint_cant_update_system_username: {
    my $user = Socialtext::User->new(username => 'system-user');
    isa_ok $user, 'Socialtext::User';

    eval { $user->update_store(email_address => 'foo@bar.com') };
    like $@, qr/cannot change/, 'constraint: cannot update "email_address" for system user';
}
