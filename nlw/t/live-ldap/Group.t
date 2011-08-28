#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests st_log);
use File::Slurp qw(write_file);
use Benchmark qw(timeit timestr);
use Socialtext::Group::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 117;
use Test::Differences qw(eq_or_diff);
use Socialtext::AppConfig;

# Force this to be synchronous.
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
# Fixtures: clean db
# - needs a DB
fixtures(qw( db ));

###############################################################################
sub bootstrap_openldap {

    for my $user (Socialtext::User->All->all()) {
        next if $user->is_system_created;
        Test::Socialtext::User->delete_recklessly($user);
    }

    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),  'added people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'), 'added groups';
    return $openldap;
}

###############################################################################
# TEST: instantiate an LDAP Group Factory
instantiate_ldap_group_factory: {
    my $openldap    = bootstrap_openldap();
    my $factory_key = $openldap->as_factory();
    my $factory = Socialtext::Group->Factory(driver_key => $factory_key);
    isa_ok $factory, 'Socialtext::Group::LDAP::Factory';
}

###############################################################################
# TEST: instantiate LDAP Group Factory, by name+id
instantiate_ldap_group_factory_by_name_and_id: {
    my $openldap = bootstrap_openldap();
    my $factory  = Socialtext::Group->Factory(
        driver_name => 'LDAP',
        driver_id   => $openldap->ldap_config->id(),
    );
    isa_ok $factory, 'Socialtext::Group::LDAP::Factory';
}

###############################################################################
# TEST: retrieve an LDAP Group
retrieve_ldap_group: {
    my $guard = Test::Socialtext::User->snapshot();

    my $openldap  = bootstrap_openldap();
    my $group_dn  = 'cn=Motorhead,dc=example,dc=com';
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $motorhead, 'Socialtext::Group';
    isa_ok $motorhead->homunculus, 'Socialtext::Group::LDAP';
    is $motorhead->driver_group_name, 'Motorhead';

    my $users = $motorhead->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '3', '... with correct number of users';

    my @users = sort {$a->user_id <=> $b->user_id} $users->all;
    my $user = shift @users;
    is $user->username => 'lemmy kilmister', '... first user has correct name';

    $user = shift @users;
    is $user->username => 'phil taylor', '... second user has correct name';

    $user = shift @users;
    is $user->username => 'eddie clarke', '... third user has correct name';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: retrieve an LDAP Group with a hash
retrieve_ldap_group_with_hash: {
    my $guard = Test::Socialtext::User->snapshot();

    my $openldap  = bootstrap_openldap();
    my $group_dn  = 'cn=#WithHash,dc=example,dc=com';
    my $group = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $group, 'Socialtext::Group';
    isa_ok $group->homunculus, 'Socialtext::Group::LDAP';
    is $group->driver_group_name, 'With Hash';

    my $users = $group->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '3', '... with correct number of users';

    my @users = sort {$a->user_id <=> $b->user_id} $users->all;
    my $user = shift @users;
    is $user->username => 'lemmy kilmister', '... first user has correct name';

    $user = shift @users;
    is $user->username => 'phil taylor', '... second user has correct name';

    $user = shift @users;
    is $user->username => 'eddie clarke', '... third user has correct name';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($group);
}

###############################################################################
# TEST: retrieve an LDAP Group, *into* a specific Account
retrieve_ldap_group_explicit_account: {
    my $openldap  = bootstrap_openldap();
    my $account   = Socialtext::Account->Socialtext();
    my $group_dn  = 'cn=Motorhead,dc=example,dc=com';
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id   => $group_dn,
        primary_account_id => $account->account_id(),
    );
    isa_ok $motorhead, 'Socialtext::Group';
    isa_ok $motorhead->homunculus, 'Socialtext::Group::LDAP';
    is $motorhead->driver_group_name, 'Motorhead';
    is $motorhead->primary_account_id, $account->account_id(),
        '... created in explicit Account';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: retrieve a *nested* LDAP Group
retrieve_nested_ldap_group: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Hawkwind,dc=example,dc=com';
    my $hawkwind = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $hawkwind, 'Socialtext::Group';
    isa_ok $hawkwind->homunculus, 'Socialtext::Group::LDAP';
    is $hawkwind->driver_group_name, 'Hawkwind';

    my $users = $hawkwind->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '4', '... with correct number of users';

    my @users = sort map { $_->username } $users->all;
    eq_or_diff \@users, [
        'eddie clarke',
        'lemmy kilmister',
        'michael moorcock',
        'phil taylor',
    ], 'have correct users';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($hawkwind);
}

###############################################################################
# TEST: retrieve a nested LDAP Group that has circular Group references
retrieve_nested_ldap_group_circular_references: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Circular A,dc=example,dc=com';
    my $circular = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $circular, 'Socialtext::Group';
    isa_ok $circular->homunculus, 'Socialtext::Group::LDAP';
    is $circular->driver_group_name, 'Circular A';

    my $users = $circular->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '2', '... with correct number of users';

    my @users = sort map { $_->username } $users->all;
    eq_or_diff \@users, [
        'michael moorcock',
        'phil taylor',
    ], 'have correct users';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($circular);
}

###############################################################################
# When a User is removed from the Group, membership list updated automatically
remove_user_from_group: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Motorhead,dc=example,dc=com';

    # get the Group, make sure it looks right
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );

    my $users = $motorhead->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '3', '... with three users';

    # expire the Group, so subsequent lookups will cause it to get refreshed
    $motorhead->expire();

    # update the Group in LDAP, removing one of its members
    my $rc = $openldap->modify(
        $group_dn,
        replace => [
            member => [
                "cn=Lemmy Kilmister,dc=example,dc=com",
                "cn=Eddie Clarke,dc=example,dc=com",
            ],
        ],
    );
    ok $rc, 'ldap store updated, user removed.';

    # re-instantiate the Group, and verify that the User was removed
    $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );

    $users = $motorhead->users;
    isa_ok $users => 'Socialtext::MultiCursor';
    is $users->count => '2', '... with two users';

    my @users = sort map { $_->username } $users->all;
    eq_or_diff \@users, [
        'eddie clarke',
        'lemmy kilmister',
    ], 'have correct users';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# Events get properly recorded when Users are added/removed
ldap_group_records_events_on_membership_change: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Motorhead,dc=example,dc=com';

    # Get the Group, make sure that the "create_role" Events were emitted
    clear_log();
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );

    my $logged = dump_log();
    like $logged, qr/ASSIGN,USER_ROLE,.*lemmy.*account:/,
        '... User/Account role assignment logged in nlw.log';
    like $logged, qr/ASSIGN,USER_ROLE,.*lemmy.*group:/,
        '... User/Group role assignment logged in nlw.log';

    like $logged, qr/ASSIGN,USER_ROLE,.*phil.*account:/,
        '... User/Account role assignment logged in nlw.log';
    like $logged, qr/ASSIGN,USER_ROLE,.*phil.*group:/,
        '... User/Group role assignment logged in nlw.log';

    like $logged, qr/ASSIGN,USER_ROLE,.*eddie.*account:/,
        '... User/Account role assignment logged in nlw.log';
    like $logged, qr/ASSIGN,USER_ROLE,.*eddie.*group:/,
        '... User/Group role assignment logged in nlw.log';

    # expire the Group, so subsequent lookups will cause it to get refreshed
    $motorhead->expire();

    # update the Group in LDAP, removing one of its members
    my $rc = $openldap->modify(
        $group_dn,
        replace => [
            member => [
                "cn=Lemmy Kilmister,dc=example,dc=com",
                "cn=Eddie Clarke,dc=example,dc=com",
            ],
        ],
    );
    ok $rc, 'ldap store updated, user removed.';

    # Re-query the Group, and make sure that the "delete_role" Event was
    # emitted
    $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );

    $logged = dump_log();
    like $logged, qr/REMOVE,USER_ROLE,.*group:/,
        '... User/Group role removal logged in nlw.log';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: Removing and Adding Users works successfully
group_remove_and_add_users_back: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Motorhead,dc=example,dc=com';
    my @users    = sort (
        'cn=Lemmy Kilmister,dc=example,dc=com',
        'cn=Eddie Clarke,dc=example,dc=com',
        'cn=Phil Taylor,dc=example,dc=com',
    );

    # Load the Group, should have expected number of Users
    my $motorhead = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    isa_ok $motorhead, 'Socialtext::Group', 'Group loaded';
    my @dns = sort map { $_->driver_unique_id } $motorhead->users->all;
    eq_or_diff \@dns, \@users, '... with expected Users';

    # Remove a User, refresh the Group; should be missing a User.
    my $rc = $openldap->modify($group_dn,
        replace => [
            member => [ $users[0], $users[1] ],
        ],
    );
    ok $rc, '... removed a User from Group';
    $motorhead->expire();
    $motorhead = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    @dns = sort map { $_->driver_unique_id } $motorhead->users->all;
    eq_or_diff \@dns, [@users[0..1]], '... ... and User count looks ok';

    # Add a User *back*, refresh the Group; should be back in the Group.
    $rc = $openldap->modify($group_dn,
        replace => [
            member => [ @users ],
        ],
    );
    ok $rc, '... added User back to the Group';
    $motorhead->expire();
    $motorhead = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    @dns = sort map { $_->driver_unique_id } $motorhead->users->all;
    eq_or_diff \@dns, \@users, '... ... and User count looks ok';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: LDAP Group lookup *re-uses* existing LDAP connection
group_lookup_reuses_ldap_connection: {
    my $openldap = bootstrap_openldap();
    my $group_dn = 'cn=Hawkwind,dc=example,dc=com';

    # Clear the LDAP connection cache, and reset its instrumentation stats
    Socialtext::LDAP->ConnectionCache->clear();
    Socialtext::LDAP->ResetStats();

    # Vivify the LDAP Group
    my $hawkwind = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $hawkwind, 'Socialtext::Group';
    isa_ok $hawkwind->homunculus, 'Socialtext::Group::LDAP';
    is $hawkwind->driver_group_name, 'Hawkwind';

    is $Socialtext::LDAP::stats{connect}, 1,
        '... using only a *single* LDAP connection';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($hawkwind);
}

###############################################################################
# TEST: List available LDAP Groups
available_ldap_groups: {
    my $openldap   = bootstrap_openldap();
    my $driver_key = $openldap->as_factory();
    my $factory    = Socialtext::Group->Factory(driver_key => $driver_key);
    isa_ok $factory, 'Socialtext::Group::LDAP::Factory';

    my $group_dn  = 'cn=Motorhead,dc=example,dc=com';
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $motorhead, 'Socialtext::Group';

    my @available = $factory->Available();
    ok @available, 'LDAP Factory has some available Groups';

    my @expected = ( {
        driver_key          => $driver_key,
        driver_group_name   => 'Motorhead',
        driver_unique_id    => 'cn=Motorhead,dc=example,dc=com',
        already_created     => 1,
        member_count        => 3,
    } );
    is_deeply \@available, \@expected, '... with correct data';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: List *ALL* available LDAP Groups
all_available_ldap_groups: {
    my $openldap   = bootstrap_openldap();
    my $driver_key = $openldap->as_factory();
    my $factory    = Socialtext::Group->Factory(driver_key => $driver_key);
    isa_ok $factory, 'Socialtext::Group::LDAP::Factory';

    my $group_dn  = 'cn=Motorhead,dc=example,dc=com';
    my $motorhead = Socialtext::Group->GetGroup(
        driver_unique_id => $group_dn,
    );
    isa_ok $motorhead, 'Socialtext::Group';

    my @available = $factory->Available( all => 1 );
    ok @available, 'LDAP Factory has some available Groups';

    my @expected = (
        {   driver_key          => $driver_key,
            driver_group_name   => 'Circular A',
            driver_unique_id    => 'cn=Circular A,dc=example,dc=com',
            already_created     => 0,
            member_count        => 2,
        },
        {   driver_key          => $driver_key,
            driver_group_name   => 'Circular B',
            driver_unique_id    => 'cn=Circular B,dc=example,dc=com',
            already_created     => 0,
            member_count        => 2,
        },
        {   driver_key          => $driver_key,
            driver_group_name   => 'Hawkwind',
            driver_unique_id    => 'cn=Hawkwind,dc=example,dc=com',
            already_created     => 0,
            member_count        => 2,
        },
        {   driver_key          => $driver_key,
            driver_group_name   => 'Motorhead',
            driver_unique_id    => 'cn=Motorhead,dc=example,dc=com',
            already_created     => 1,
            member_count        => 3,
        },
        {   driver_key          => $driver_key,
            driver_group_name   => 'With Hash',
            driver_unique_id    => 'cn=#WithHash,dc=example,dc=com',
            already_created     => 0,
            member_count        => 3,
        },
    );
    is_deeply \@available, \@expected, '... with correct data';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($motorhead);
}

###############################################################################
# TEST: PERF test with *BIG* Groups
perf_test_big_ldap_groups: {
    SKIP: {
        skip "Benchmark tests skipped; set NLW_BENCHMARK=1 to run them", 12
            unless ($ENV{NLW_BENCHMARK});
        diag "Benchmark tests running, this may take a while...";

        # Fire up OpenLDAP
        my $openldap = bootstrap_openldap();
        my $t;

        # Create a test set of Groups
        # ... some of which are small
        # ... some of which are *HUGE*
        diag "Feeding Group data to OpenLDAP...";
        $t = timeit(1, sub {
            _add_group_to_ldap(ldap => $openldap, users => 20);
            _add_group_to_ldap(ldap => $openldap, users => 50);
            _add_group_to_ldap(ldap => $openldap, users => 70);
            _add_group_to_ldap(ldap => $openldap, users => 2000);
            _add_group_to_ldap(ldap => $openldap, users => 5000);
            _add_group_to_ldap(ldap => $openldap, users => 20000);
            _add_group_to_ldap(ldap => $openldap, users => 30000);
            } );
        diag "... " . timestr($t);

        # how long does it take to do "$factory->available(all=>1)" ?
        diag "Querying list of available Groups...";
        $t = timeit(1, sub {
            my $driver    = $openldap->as_factory();
            my $factory   = Socialtext::Group->Factory(driver_key => $driver);
            my @available = $factory->Available(all => 1);

            # check Group count (our Groups, plus default ones)
            is scalar @available, 11, 'Right number of available Groups';

            # make sure total User count matches up
            my $total_expected = 57140;
            my $total_users    = 0;
            foreach my $group (@available) {
                next unless ($group->{driver_group_name} =~ /Test Group/);
                $total_users += $group->{member_count};
            }
            is $total_users, $total_expected, '... and correct number of test Users';
        } );
        diag "... " . timestr($t);
    }

    my $counter = 0;
    sub _add_group_to_ldap {
        my %opts  = @_;
        my $ldap  = $opts{ldap};
        my $users = $opts{users};

        # create LDIF for this Group
        # - note that we don't actually have to add inetOrgPerson entries for
        #   each of the Users; we're not vivifying the Users but instead are
        #   testing how long it takes to suck down the Group info from
        #   OpenLDAP.
        my $cn   = "Test Group " . $counter++;
        my $dn   = "cn=$cn,dc=example,dc=com";
        my $ldif = qq{
dn: $dn
objectClass: groupOfNames
cn: $cn
};
        for (1 .. $users) {
            my $user_cn = "User " . $counter++;
            my $user_dn = "cn=$user_cn,dc=example,dc=com";
            $ldif .= "member: $user_dn\n";
        }

        # add Group to OpenLDAP
        my $test_dir = Socialtext::AppConfig->test_dir();
        my $filename = "$test_dir/ldap-list-group-perf.$$";
        write_file($filename, $ldif);
        ok $ldap->add_ldif($filename), "... adding Group w/$users Users";
        unlink $filename;
    }
}
