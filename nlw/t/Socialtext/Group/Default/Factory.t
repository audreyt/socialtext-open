#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 36;
use Test::Socialtext::Group;

###############################################################################
# Fixtures: db
# - need a DB to work with, but don't care what's in it.
fixtures(qw( db ));

use_ok 'Socialtext::Group::Default::Factory';

###############################################################################
# TEST: instantiation, no parameters
instantiation_no_parameters: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';
}

###############################################################################
# TEST: Default Group Factory *is* updateable
default_group_factory_is_updateable: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';
    ok $factory->can_update_store(), '... and is updateable';
}

###############################################################################
# TEST: create a new Group object
create_group: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    my $account = create_test_account_bypassing_factory();
    my $creator = create_test_user(account => $account);
    my $test_start = $factory->Now();
    my $group = $factory->Create( {
        driver_group_name   => 'Test Group',
        primary_account_id  => $account->account_id(),
        created_by_user_id  => $creator->user_id(),
    } );
    my $test_finish = $factory->Now();
    isa_ok $group, 'Socialtext::Group::Default';

    # verify Group attributes
    ok $group->group_id,   '... has an assigned group_id';
    is $group->driver_key, $factory->driver_key,
        '... with driver_key matching factory';
    is $group->driver_name, $factory->driver_name,
        '... with driver_name matching factory';
    is $group->driver_id, $factory->driver_id,
        '... with driver_id matching factory';
    is $group->driver_unique_id, $group->group_id,
        '... group_id matches driver_unique_id (for Default Groups)';
    is $group->driver_group_name, 'Test Group',
        '... with driver_group_name matching provided Group Name';
    is $group->primary_account_id, $account->account_id(),
        '... with provided primary Account Id';
    is $group->created_by_user_id, $creator->user_id(),
        '... with provided creator User Id';

    my $created_when = $group->creation_datetime;
    ok $created_when > $test_start,
        '... created after our test started';
    ok $created_when < $test_finish,
        '... ... and before our test finished (so we must have created it)';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($group);
}

###############################################################################
# TEST: delete a Group object
delete_group: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    # create a Group that we can monkey with
    my $account = create_test_account_bypassing_factory();
    my $creator = create_test_user(account => $account);
    my $group = $factory->Create( {
        driver_group_name   => 'Test Group',
        primary_account_id  => $account->account_id(),
        created_by_user_id  => $creator->user_id(),
    } );
    isa_ok $group, 'Socialtext::Group::Default';

    # retrieve Group; it should be there
    my $queried = $factory->GetGroupHomunculus( group_id => $group->group_id );
    isa_ok $queried, 'Socialtext::Group::Homunculus', '... queried Homunculus';

    # delete Group
    ok $factory->Delete($queried), '... which can be deleted';

    # retrieve Group should return empty-handed
    $queried = $factory->GetGroupHomunculus( group_id => $group->group_id );
    ok !$queried, "... and which can't be queried after deletion";
}

###############################################################################
# TEST: cannot delete non-existent Group
delete_nonexistent_group: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    # create a Group that we can monkey with
    my $account = create_test_account_bypassing_factory();
    my $creator = create_test_user(account => $account);
    my $group = $factory->Create( {
        driver_group_name   => 'Test Group',
        primary_account_id  => $account->account_id(),
        created_by_user_id  => $creator->user_id(),
    } );
    isa_ok $group, 'Socialtext::Group::Default';

    # delete Group
    ok  $factory->Delete($group), '... which can be deleted';
    ok !$factory->Delete($group), '... ... but only once';
}

###############################################################################
# TEST: trying to delete Group without Group object throws error
delete_group_without_group_object: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    my $rc = eval { $factory->Delete() };
    ok !$rc, 'delete Group fails with no Group provided';
    ok $@, '... and it throws an exception (regardless of how ugly it may be)';
}

###############################################################################
# TEST: trying to delete a Group Record without Group Id throws error
delete_group_record_without_id: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    my $rc = eval { $factory->DeleteGroupRecord() };
    ok !$rc, 'deleting Group record fails when no group_id';
    like $@, qr/Cannot accurately identify unique record to delete/,
        '... throwing exception about no group_id';
}

###############################################################################
# TEST: List available Groups
available_groups: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    my $account = create_test_account_bypassing_factory();
    my $creator = create_test_user(account => $account);

    my $homey_1 = $factory->Create( {
        driver_group_name   => 'Test Group One',
        primary_account_id  => $account->account_id(),
        created_by_user_id  => $creator->user_id(),
    } );
    my $group_1 = Socialtext::Group->new(homunculus => $homey_1);
    $group_1->add_user( user => create_test_user() );
    $group_1->add_user( user => create_test_user() );
    $group_1->add_user( user => create_test_user() );

    my $homey_2 = $factory->Create( {
        driver_group_name   => 'Test Group Two',
        primary_account_id  => $account->account_id(),
        created_by_user_id  => $creator->user_id(),
    } );
    my $group_2 = Socialtext::Group->new(homunculus => $homey_2);
    $group_2->add_user( user => create_test_user() );
    $group_2->add_user( user => create_test_user() );

    my @available = $factory->Available();
    ok @available, 'Queried available Groups';
    my @expected = (
        {   driver_key          => 'Default',
            driver_group_name   => 'Test Group One',
            driver_unique_id    => $group_1->driver_unique_id,
            already_created     => 1,
            member_count        => $group_1->user_count(),
        },
        {   driver_key          => 'Default',
            driver_group_name   => 'Test Group Two',
            driver_unique_id    => $group_2->driver_unique_id,
            already_created     => 1,
            member_count        => $group_2->user_count(),
        },
    );
    is_deeply \@available, \@expected, '... available Groups data ok';
}

###############################################################################
# TEST: group_id must be numeric.
group_id_must_be_numeric: {
    my $factory = Socialtext::Group::Default::Factory->new();
    isa_ok $factory, 'Socialtext::Group::Default::Factory';

    my $group = $factory->GetGroupHomunculus( group_id => 'is_a_string' );
    ok !$group, 'return undef if group_id is non-numberic';
}
