#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 21;
use Socialtext::Account;
use Socialtext::User;

###############################################################################
# Fixtures: db
# - Need a DB around, but don't care what's in it.
fixtures(qw( db ));

use_ok 'Socialtext::Group::Homunculus';

###############################################################################
### TEST DATA
###############################################################################
my %TEST_DATA = (
    group_id           => 123,
    driver_key         => 'Dummy:abc123',
    driver_unique_id   => 456,
    driver_group_name  => 'Test Group Name',
    creation_datetime  => DateTime->from_epoch( epoch => 1234567890 ),
    cached_at          => DateTime->from_epoch( epoch => 1234560000 ),
    created_by_user_id => Socialtext::User->SystemUser->user_id(),
    primary_account_id => Socialtext::Account->Socialtext->account_id(),
);

###############################################################################
# TEST: Group Homunculus instantiation
instantiation: {
    my $homey = Socialtext::Group::Homunculus->new(%TEST_DATA);
    isa_ok $homey, 'Socialtext::Group::Homunculus', 'Group Homunculus';

    # verify all the attributes (lazily built or otherwise) are as expected
    is $homey->group_id, $TEST_DATA{group_id}, '... with group_id';
    is $homey->driver_key, $TEST_DATA{driver_key}, '... with driver_key';
    is $homey->driver_name, 'Dummy', '... ... containing driver_name';
    is $homey->driver_id, 'abc123', '... ... containing driver_id';
    is $homey->driver_group_name, $TEST_DATA{driver_group_name},
        '... with driver_group_name';
    is $homey->display_name, $TEST_DATA{driver_group_name},
        '... with display_name alias';
    is $homey->creation_datetime->epoch, $TEST_DATA{creation_datetime}->epoch,
        '... with creation_datetime';
    is $homey->cached_at->epoch, $TEST_DATA{cached_at}->epoch,
        '... with cached_at';

    is $homey->created_by_user_id, $TEST_DATA{created_by_user_id},
        '... with created_by_user_id';
    isa_ok $homey->creator, 'Socialtext::User',
        '... ... vivified User';
    is $homey->creator->user_id, $TEST_DATA{created_by_user_id},
        '... ... ... with matching user_id';

    is $homey->primary_account_id, $TEST_DATA{primary_account_id},
        '... with primary_account_id';
    isa_ok $homey->primary_account, 'Socialtext::Account',
        '... ... vivified primary Account';
    is $homey->primary_account->account_id, $TEST_DATA{primary_account_id},
        '... ... ... with matching account_id';

    ok $homey->is_system_managed, '... is system managed';
}

###############################################################################
# TEST: User created Group Homunuculus is not system managed
user_created_group_not_system_managed: {
    my $user = create_test_user();
    isa_ok $user, 'Socialtext::User', 'Test User';

    my $homey = Socialtext::Group::Homunculus->new( {
        %TEST_DATA,
        created_by_user_id => $user->user_id(),
        } );
    isa_ok $homey, 'Socialtext::Group::Homunculus', 'Group Homunculus';

    is $homey->created_by_user_id, $user->user_id,
        '... created by our Test User';
    ok !$homey->is_system_managed, '... Group is not system managed';
}
