#!/usr/bin/env perl

use strict;
use warnings;
use Test::Socialtext tests => 9;
use Test::Socialtext::User;
use Socialtext::User;

fixtures(qw( db ));

###############################################################################
# TEST: Create a User from scratch, with a private external Id
create_with_private_external_id: {
    my $private_id = time . "-$$-external-id";
    my $uniq_id    = Test::Socialtext->create_unique_id();
    my $email      = $uniq_id . '@ken.socialtext.net';

    my $user = Socialtext::User->create(
        username            => $email,
        email_address       => $email,
        password            => 'bogus-password',
        no_crypt            => 1,
        private_external_id => $private_id,
    );
    isa_ok $user, 'Socialtext::User', 'Created test user w/private id';
    is $user->private_external_id, $private_id, '... private id was set';

    # CLEANUP
    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: Update an existing User to  have a private external Id
update_private_external_id: {
    my $private_id = time . "-$$-external-id";
    my $user       = create_test_user();
    isa_ok $user, 'Socialtext::User', 'Created test user';

    my $rc = $user->update_store(private_external_id => $private_id);
    ok $rc, '... updated the Private External Id';

    is $user->private_external_id, $private_id, '... and was set';

    # CLEANUP
    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: Look up a User record by private external Id
lookup_by_private_external_id: {
    my $private_id = time . "-$$-external-id";
    my $user       = create_test_user(private_external_id => $private_id);

    my $lookup = Socialtext::User->new(private_external_id => $private_id);
    isa_ok $lookup, 'Socialtext::User', 'Found User by private id';

    is $lookup->username, $user->username,
        '... and its the User we created';

    # CLEANUP
    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: Make sure that the private external Id field requires unique-ness
attempt_duplicate_private_external_id: {
    my $private_id = time . "-$$-external-id";
    my $user_one = create_test_user();
    my $user_two = create_test_user();

    my $rc = $user_one->update_store(private_external_id => $private_id);
    ok $rc, 'Updated first User to have a private id';

    eval {
        $user_two->update_store(private_external_id => $private_id);
    };
    like $@, qr/The private external id.*is already in use/,
        '... cannot update another User to have same private id';

    # CLEANUP
    Test::Socialtext::User->delete_recklessly($user_one);
    Test::Socialtext::User->delete_recklessly($user_two);
}
