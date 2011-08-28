#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 118;
use Test::Socialtext::User;
use Socialtext::User;
use Socialtext::SQL qw(sql_execute);

###############################################################################
# Fixtures: clean db
# - need to clean out the DB first; our tests explicitly expect a
#   "fresh/clean" DB to work against.
fixtures(qw( clean db ));

use_ok 'Socialtext::User::Default::Factory';

my $start_time = time;
my $user_counter = 0;

sub next_username {
    $user_counter++;
    print "# username $user_counter\n";
    return "${start_time}u$user_counter\@ken.socialtext.net";
}

sub create_a_user {
    my %opts = @_;

    my $factory = delete $opts{factory};
    $factory ||= Socialtext::User::Default::Factory->new();

    my $expected_email = delete $opts{expected_email};
    $expected_email ||= lc $opts{email_address};
    my $expected_username = delete $opts{expected_username};
    $expected_username ||= lc $opts{username};

    my $user = $factory->create(%opts);

    isa_ok $user, 'Socialtext::User::Default', 'created new user';

    is $user->email_address, $expected_email, '... email_address is correct'
        if defined $opts{email_address};

    is $user->username, $expected_username, '... username is correct'
        if defined $opts{username};

    if (defined $opts{password} && !$opts{no_crypt}) {
        isnt $user->password, $opts{password}, '... password appears encrypted';
        ok $user->password_is_correct($opts{password}), 
            '... password was encrypted correctly';
    }

    ok $user->user_id, '... got assigned a user_id';

    return $user unless wantarray;
    return ($factory, $user);
}

###############################################################################
# Factory instantiation with no parameters.
instantiation_no_parameters: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';
}

###############################################################################
# Factory instantiation with parameters (which are actually just ignored)
instantiation_named_factory: {
    my $factory = Socialtext::User::Default::Factory->new('Ignored Parameter');
    isa_ok $factory, 'Socialtext::User::Default::Factory';
}

###############################################################################
# Count number of configured users; initial set should always have two users.
count_initial_users: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    is $factory->Count(), 2, 'expected to find two initial users';
}

###############################################################################
# Verify initial users that we ALWAYS have available
verify_initial_users: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my $user_system = $factory->GetUser(username => 'system-user');
    isa_ok $user_system, 'Socialtext::User::Default', '... system user exists';
    is $user_system->username, 'system-user', '... ... and its the right user';

    my $user_guest  = $factory->GetUser(username => 'guest');
    isa_ok $user_guest, 'Socialtext::User::Default', '... guest user exists';
    is $user_guest->username, 'guest', '... ... and its the right user';
}

###############################################################################
# Create a new user record
create_new_user: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    # hold onto the current user count; we'll check it after creating the new
    # user.
    my $orig_count = $factory->Count();

    # create the new user record and verify the results
    my $username = next_username();
    my $user = create_a_user(
        factory       => $factory,
        username      => $username,
        email_address => $username,
        password      => 'password',
    );

    # make sure user got added to DB correctly
    is $factory->Count(), $orig_count+1, '... user count incremented';

    # delete the user, make sure count goes down correctly.
    my $st_user = Socialtext::User->new( user_id => $user->user_id );
    isa_ok $st_user, 'Socialtext::User', '... main user object';
    Test::Socialtext::User->delete_recklessly($st_user);
    is $factory->Count(), $orig_count, '... ... user count decremented when user deleted';
}

###############################################################################
# Create a new user record with an ALREADY ENCRYPTED password
create_new_user_unencrypted_password: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    # hold onto the current user count; we'll check it after creating the new
    # user
    my $orig_count = $factory->Count();

    # create the new user record and verify the results
    my $password = 
        Socialtext::User::Default->_encode_password('password');
    my $username = next_username();
    my $user = create_a_user(
        factory => $factory,
        username        => $username,
        email_address   => $username,
        password        => $password,
        no_crypt        => 1,
    );

    is $user->password, $password, '... password NOT encrypted';
    ok $user->password_is_correct('password'), '... UN-encrypted password is correct';

    # make sure user got added to DB correctly
    is $factory->Count(), $orig_count+1, '... user count incremented';
}

###############################################################################
# Creating a new user does perform data cleanup/validation.
creating_new_user_does_data_cleanup: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my $username = next_username();
    my $user = create_a_user(
        username          => uc($username),
        expected_username => $username,
        email_address     => '   '.uc($username).'   ',
        expected_email    => $username,
        password          => 'password',
    );

    is $user->username, $username, '... username was lower-cased';
    is $user->email_address(), $username, '... email_address was lower-cased and cleaned up';
}

###############################################################################
# Verify list of valid search terms when retrieving a user record
get_user_valid_search_terms: {
    # create user record to search for
    my $username = next_username();
    my %opts = (
        username      => $username,
        email_address => $username,
        password      =>
            Socialtext::User::Default->_encode_password('password'),
        no_crypt => 1,
    );
    my ($factory, $user) = create_a_user(%opts);

    # "username" is a valid search term
    my $found = $factory->GetUser(username => $opts{username});
    isa_ok $found, 'Socialtext::User::Default', '... username; valid search term';

    # "user_id" is a valid search term
    $found = $factory->GetUser(user_id => $user->user_id());
    isa_ok $found, 'Socialtext::User::Default', '... user_id; valid search term';

    # "email_address" is a valid search term
    $found = $factory->GetUser(email_address => $opts{email_address});
    isa_ok $found, 'Socialtext::User::Default', '... email_address; valid search term';

    # "password" isn't a valid search term
    $found = $factory->GetUser(password => $opts{password});
    ok !defined $found, '... password: INVALID search term';
}

###############################################################################
# Verify that retrieving a user record with blank/undefined value returns
# empty handed.
get_user_blank_value: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my $user = $factory->GetUser(username => undef);
    ok !defined $user, 'get user w/undef value returns empty-handed';
}

###############################################################################
# Verify that retrieving an unknown user returns empty handed.
get_user_unknown_user: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my $user = $factory->GetUser(username => 'missing-user@socialtext.net');
    ok !defined $user, 'get unknown user returns empty-handed';
}

###############################################################################
# User retrieval via "username"
get_user_via_username: {
    my $username = next_username();
    my %opts = (
        username      => $username,
        email_address => $username,
        password      => 'password',
    );
    my ($factory, $user) = create_a_user(%opts);

    # dig the user out, via "username"
    my $found = $factory->GetUser(username => $opts{username});
    isa_ok $found, 'Socialtext::User::Default', '... found user via "username"';
    is $found->email_address(), $opts{email_address}, '... and its the right user';
    is $found->user_id, $user->user_id, '... it\'s the same user';

    # User retrieval via "username" is case IN-sensitive
    my $found2 = $factory->GetUser(username => uc($opts{username}));
    isa_ok $found2, 'Socialtext::User::Default', '... found user via "username" (case IN-sensitively)';
    is $found2->email_address(), $opts{email_address}, '... and its the right user';
    is $found2->user_id, $user->user_id, '... it\'s the same user';
}

###############################################################################
# User retrieval via "email_address"
get_user_via_email_address: {
    my $username = next_username();
    my %opts = (
        username        => $username,
        email_address   => $username,
        password        => 'password',
    );
    my ($factory, $user) = create_a_user(%opts);

    # dig the user out, via "email_address"
    my $found = $factory->GetUser(email_address => $opts{email_address});
    isa_ok $found, 'Socialtext::User::Default', '... found user via "email_address"';
    is $found->username(), $opts{username}, '... and its the right user';
    is $found->user_id, $user->user_id, '... is the same user';
}

###############################################################################
# User retrieval via "user_id"
get_user_via_user_id: {
    my $username = next_username();
    my %opts = (
        username        => $username,
        email_address   => $username,
        password        => 'password',
    );
    my ($factory, $user) = create_a_user(%opts);

    # dig the user out, via "user_id"
    my $found = $factory->GetUser(user_id => $user->user_id);
    isa_ok $found, 'Socialtext::User::Default', '... found user via "user_id"';
    is $found->email_address(), $user->email_address(), '... and its the right user';
    is $found->user_id, $user->user_id, '... and has the right user_id';
}

###############################################################################
# User retrieval with non-numeric "user_id" returns empty-handed (as opposed
# to throwing a DB error)
get_user_non_numeric_user_id: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';

    my $found = $factory->GetUser(user_id => 'something non-numeric');
    ok !defined $found, '... returned empty-handed with non-numeric user_id';
}

###############################################################################
# Update user record (directly against factory)
update_user_via_factory: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';
    my $orig_count = $factory->Count();

    # create a user to update
    my $username = next_username();
    my %opts = (
        username      => $username,
        email_address => $username,
        password      => 'password',
    );
    my $user = Socialtext::User->create( %opts );
    isa_ok $user, 'Socialtext::User', 'created new user _indirectly_';
    ok $user->user_id, '... user has a user_id';
    is $factory->Count, $orig_count+1, '... user is actually new';

    my $homunculus = $user->homunculus;
    isa_ok $homunculus, 'Socialtext::User::Default', '... is a Default homunculus';

    # update the user record (via the factory)
    my $rc = $factory->update( $homunculus, username => 'bleargh' );
    ok $rc, '... updated users "username" (via factory)';

    # yank user out of DB again and verify update
    my $found = $factory->GetUser( username => 'bleargh' );
    $found->profile; # Trigger profile instantiation (since it is lazy)
    isa_ok $found, 'Socialtext::User::Default', '... found updated user';
    is_deeply $found, $homunculus, '... homunculus matches';
    is $found->user_id, $user->user_id, '... same user_id';
}

###############################################################################
# Update user record (using helper method in ST::User::Default)
update_user_via_user: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';
    my $orig_count = $factory->Count();

    # create a user to update
    my $username = next_username();
    my %opts = (
        username      => $username,
        email_address => $username,
        password      => 'password',
    );
    my $user = Socialtext::User->create( %opts );
    isa_ok $user, 'Socialtext::User',
        'created new user _indirectly_ (for update via user)';
    ok $user->user_id, '... user has a user_id';
    is $factory->Count, $orig_count+1, '... user is actually new';

    my $homunculus = $user->homunculus();
    isa_ok $homunculus, 'Socialtext::User::Default', '... is a Default homunculus';

    # update the user record
    my $rc = $homunculus->update( email_address => 'foo@example.com' );
    ok $rc, '... updated users "email_address" (via user record)';

    # yank user out of DB again and verify update
    my $found = $factory->GetUser( email_address => 'foo@example.com' );
    $found->profile; # Trigger profile instantiation (since it is lazy)
    isa_ok $found, 'Socialtext::User::Default', '... found updated user';
    is_deeply $found, $homunculus, '... homunculus matches';
    is $found->user_id, $user->user_id, '... same user_id';
}

###############################################################################
# Updating a user does perform data cleanup/validation.
updating_user_does_data_cleanup: {
    my $factory = Socialtext::User::Default::Factory->new();
    isa_ok $factory, 'Socialtext::User::Default::Factory';
    my $orig_count = $factory->Count();

    # create a user to update
    my $username = next_username();
    my %opts = (
        username      => $username,
        email_address => $username,
        password      => 'password',
    );
    my $user = Socialtext::User->create( %opts );
    isa_ok $user, 'Socialtext::User', 'created new user';
    ok $user->user_id, '... user has a user_id';
    is $factory->Count, $orig_count+1, '... user is actually new';

    my $homunculus = $user->homunculus();
    isa_ok $homunculus, 'Socialtext::User::Default', '... is a Default homunculus';

    # update the user record
    my $rc = $homunculus->update( email_address => '  FOO@BAR.COM   ' );
    ok $rc, '... user record updated';
    is $homunculus->email_address(), 'foo@bar.com', '... and cleanup was performed';
}

bad_driver_key_means_deleted: {
    my $username = next_username();
    my %opts = (
        username        => $username,
        email_address   => $username,
        password        => 'password',
    ); 
    my ($factory, $user) = create_a_user(%opts);

    sql_execute(q{
        UPDATE users
        SET driver_key = 'LDAP:doesntexist'
        WHERE user_id = ?
    }, $user->user_id);

    my $found = Socialtext::User->new(user_id => $user->user_id);
    ok $found, "was still able to find the user...";
    ok $found->is_deleted(), "... and its a deleted user";

    my $found2 = Socialtext::User->new(username => $user->username);
    ok $found2, "was still able to find the user...";
    ok $found2->is_deleted(), "... and its a deleted user";

    my $found3 = Socialtext::User->new(email_address => $user->email_address);
    ok $found3, "was still able to find the user...";
    ok $found3->is_deleted(), "... and its a deleted user";
}
