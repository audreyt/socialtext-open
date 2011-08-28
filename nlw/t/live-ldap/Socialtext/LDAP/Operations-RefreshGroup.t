#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 38;
use Test::Socialtext::Group;
use File::Slurp qw(write_file);
use Benchmark qw(timeit timestr);
use Socialtext::SQL qw(:exec);
use Socialtext::Date;
use Socialtext::LDAP::Operations;

# no point in using the ceqlotron for these tests
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
# FIXTURE: db
# - Need a DB, but don't care what's in it.
fixtures(qw( db ));

###############################################################################
### TEST DATA
our $GROUP_DN = 'cn=Motorhead,dc=example,dc=com';

###############################################################################
# Sets up OpenLDAP, adds some test data, and adds the OpenLDAP server to our
# list of Group Factories.
sub set_up_openldap {
    my $groups_file = shift || 't/test-data/ldap/groups-groupOfNames.ldif';
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();

    $openldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $openldap->add_ldif('t/test-data/ldap/people.ldif');
    $openldap->add_ldif($groups_file);
    return $openldap;
}

###############################################################################
# TEST: if we've got *NO* LDAP Groups, refresh doesn't choke.
test_no_ldap_groups: {
    Socialtext::LDAP::Operations->RefreshGroups();
    logged_like 'info', qr/found 0 LDAP groups/, '... no LDAP groups present';
}

###############################################################################
# TEST: have LDAP Groups, but they're all fresh; not refreshed again.
test_ldap_groups_all_fresh: {
    my $ldap = set_up_openldap();

    # add an LDAP Group to our DB cache
    my $ldap_group = Socialtext::Group->GetGroup(driver_unique_id => $GROUP_DN);
    isa_ok $ldap_group, 'Socialtext::Group', 'LDAP group';

    my $ldap_homey = $ldap_group->homunculus;
    isa_ok $ldap_homey, 'Socialtext::Group::LDAP', 'LDAP homunculus';

    # refresh LDAP Groups
    Socialtext::LDAP::Operations->RefreshGroups();
    logged_like 'info', qr/found 1 LDAP groups/, 'one LDAP group present';

    # get the refreshed LDAP Group record
    my $refreshed_group = Socialtext::Group->GetGroup(
        driver_unique_id => $GROUP_DN,
    );
    isa_ok $refreshed_group, 'Socialtext::Group', 'refreshed LDAP group';

    my $refreshed_homey = $refreshed_group->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::Group::LDAP', 'refreshed LDAP homunculus';

    # make sure that we've got different copies of the Group object, *but* that
    # they were both cached at the same time (e.g. we didn't just refresh the
    # group).
    isnt $ldap_homey, $refreshed_homey, 'group objects are different';
    is $refreshed_homey->cached_at->hires_epoch,
        $ldap_homey->cached_at->hires_epoch,
        'group was not refreshed; was already fresh';

    # cleanup; don't want to pollute other tests
    Test::Socialtext::Group->delete_recklessly($ldap_group);
}

###############################################################################
# TEST: have LDAP Groups, some of which have never been cached; users that have
# never been cached are refreshed.
#
# We *also* test here to make sure that the first_name/last_name/username are
# refreshed properly.  This is then skipped in subsequent tests (as we've
# already tested for that condition here).
test_refresh_stale_groups: {
    my $ldap = set_up_openldap();

    # add an LDAP user to our DB cache
    my $ldap_group = Socialtext::Group->GetGroup( 
        driver_unique_id => $GROUP_DN );
    isa_ok $ldap_group, 'Socialtext::Group', 'LDAP group';

    my $ldap_homey = $ldap_group->homunculus;
    isa_ok $ldap_homey, 'Socialtext::Group::LDAP', 'LDAP homunculus';

    # update the DB with new info, so we'll be able to verify that the user
    # did in fact get his/her data refreshed from LDAP again.
    sql_execute( qq{
        UPDATE groups 
           SET driver_group_name = 'Not-Motorhead'
         WHERE driver_unique_id=?
        }, $ldap_homey->driver_unique_id );
    my $bogus_group = Socialtext::Group->GetGroup( 
        driver_unique_id => $GROUP_DN );
    is $bogus_group->driver_group_name, 'Not-Motorhead',
        'set bogus data for group name';

    # expire the user, so that they'll get refreshed
    $ldap_homey->expire();

    # refresh LDAP groups 
    my $time_before_refresh = Socialtext::Date->now( hires => 1 );
    {
        Socialtext::LDAP::Operations->RefreshGroups();
        logged_like 'info', qr/found 1 LDAP groups/, 'one LDAP group present';
    }
    my $time_after_refresh = Socialtext::Date->now( hires => 1 );

    # get the refreshed LDAP user record
    my $refreshed_group = Socialtext::Group->GetGroup(
        driver_unique_id => $GROUP_DN );
    isa_ok $refreshed_group, 'Socialtext::Group', 'refreshed LDAP group';

    my $refreshed_homey = $refreshed_group->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::Group::LDAP',
        'refreshed LDAP homunculus';

    # make sure the user *was* refreshed by the call to RefreshGroups()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(),
        'group was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(),
        '... by RefreshGroups()';

    # make sure that the bogus data we set into the user was over-written by
    # the refresh
    is $refreshed_homey->driver_group_name, 'Motorhead',
        '... group name was refreshed';

    # cleanup; don't want to pollute other tests
    Test::Socialtext::Group->delete_recklessly($ldap_group);
}

###############################################################################
# TEST: have LDAP users, force the refresh; *all* users are refreshed
# regardless of whether they're fresh/stale.
test_force_refresh: {
    my $ldap = set_up_openldap();

    # add an LDAP group to our DB cache
    my $ldap_group = Socialtext::Group->GetGroup(
        driver_unique_id => $GROUP_DN );
    isa_ok $ldap_group, 'Socialtext::Group', 'LDAP group';

    my $ldap_homey = $ldap_group->homunculus;
    isa_ok $ldap_homey, 'Socialtext::Group::LDAP', 'LDAP homunculus';

    # refresh LDAP Groups 
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshGroups(force => 1);
        logged_like 'info', qr/found 1 LDAP groups/, 'one LDAP group present';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # get the refreshed LDAP group record
    my $refreshed_group = Socialtext::Group->GetGroup(
        driver_unique_id => $GROUP_DN );
    isa_ok $refreshed_group , 'Socialtext::Group', 'refreshed LDAP group ';

    my $refreshed_homey = $refreshed_group ->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::Group::LDAP',
        'refreshed LDAP homunculus';

    # make sure the group *was* refreshed by RefreshGroups()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(),
        'group was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(),
        '... by RefreshGroups()';

    # cleanup; don't want to pollute other tests
    Test::Socialtext::Group->delete_recklessly($ldap_group );
}

###############################################################################
# TEST: refresh a single LDAP Group, by group_id
test_refresh_group_by_id: {
    my $ldap = set_up_openldap();
    my $other_dn = 'cn=Hawkwind,dc=example,dc=com';

    # add some LDAP Groups
    my $ldap_group = Socialtext::Group->GetGroup(driver_unique_id => $GROUP_DN);
    my $ldap_homey = $ldap_group->homunculus;

    my $other_group = Socialtext::Group->GetGroup(driver_unique_id => $other_dn);
    my $other_homey = $other_group->homunculus;

    # refresh LDAP Groups
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshGroups(
            force => 1,
            id    => $ldap_group->group_id,
        );
        logged_like 'info', qr/found 1 LDAP groups/,
            'one LDAP group refreshed, by Id';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # VERIFY: Group was refreshed by RefreshGroups()
    my $refreshed_group = Socialtext::Group->GetGroup(driver_unique_id => $GROUP_DN);
    my $refreshed_homey = $refreshed_group->homunculus;

    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'group was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(),  '... by RefreshGroups()';

    # VERIFY: Other Group was *not* refreshed
    $refreshed_group = Socialtext::Group->GetGroup(driver_unique_id => $other_dn);
    $refreshed_homey = $refreshed_group->homunculus;

    $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at < $time_before_refresh->hires_epoch(), 'other group was NOT refreshed';

    # cleanup; don't want to pollute other tests
    Test::Socialtext::Group->delete_recklessly($ldap_group);
    Test::Socialtext::Group->delete_recklessly($other_group);
}

###############################################################################
# TEST: a User w/invalid data doesn't kill Group refreshes; the Group should
# be able to refresh without him.
user_w_missing_email_doesnt_kill_group_refresh: {
    my $ldap = set_up_openldap();

    # set up custom LDAP config, so we can create Users with invalid data
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    # valid/invalid Users, and a Group containing both
    my $valid_dn    = 'cn=Blue Valkyrie,dc=example,dc=com';
    my %valid_attrs = (
        objectClass => 'inetOrgPerson',
        cn          => 'Blue Valkyrie',
        gn          => 'Blue',
        sn          => 'Valkyrie',
        title       => 'blue.valkyrie@example.com',
    );

    my $invalid_dn = 'cn=Yellow Wizard,dc=example,dc=com';
    my %invalid_attrs = (
        objectClass => 'inetOrgPerson',
        cn          => 'Yellow Wizard',
        gn          => 'Yellow',
        sn          => 'Wizard',
    );

    my $group_dn    = 'cn=Gauntlet Characters,dc=example,dc=com';
    my %group_attrs = (
        objectClass => 'groupOfNames',
        cn          => 'Gauntlet Characters',
        member      => [ $valid_dn, $invalid_dn ],
    );

    # add the test data to LDAP
    my $rc;
    $rc = $ldap->add($valid_dn, %valid_attrs);
    ok $rc, 'added valid User to LDAP';

    $rc = $ldap->add($invalid_dn, %invalid_attrs);
    ok $rc, 'added invalid User to LDAP';

    $rc = $ldap->add($group_dn, %group_attrs);
    ok $rc, 'added Group to LDAP';

    # instantiate the Group, which should load it into the system ok
    clear_log();
    my $group = eval {
        Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    };
    ok $group, 'Group instantiation successful';
    is $group->user_count, 1, '... with correct number of valid Users';
    logged_like 'warning',
        qr/Unable to refresh.*'$invalid_dn'.*Email address is a required field/,
        '... recording warning about missing e-mail';

    # force a refresh of the Group, it should refresh successfully and just
    # skip the User that has no e-mail address.
    {
        clear_log();
        Socialtext::LDAP::Operations->RefreshGroups(force => 1);
        logged_like 'info', qr/refreshing: $group_attrs{cn}/,
            '... Group refreshed';
        logged_like 'warning',
            qr/Unable to refresh.*'$invalid_dn'.*Email address is a required field/,
            '... recording warning about missing e-mail';

        my $refreshed = eval {
            Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
        };
        ok $refreshed, '... refreshed Group instantiation successful';
        is $refreshed->user_count, 1, '... ... with correct number of valid Users';
    }
}


###############################################################################
# BENCHMARK: how long does it take to refresh 1000 Groups with 1 User each?
# total records: 2000
benchmark_tiny_groups: {
    unless ($ENV{NLW_BENCHMARK}) {
        diag "Tiny group benchmark tests skipped; set NLW_BENCHMARK=1 to run them";
    }
    else {
        diag "Running benchmark for tiny groups; this may take a while.";
        _do_benchmark( 1000, 1 );
    }
}

###############################################################################
# BENCHMARK: how long does it take to refresh 200 Groups with 5 Users each?
# total records: 1200
benchmark_medium_groups: {
    unless ($ENV{NLW_BENCHMARK}) {
        diag "Medium group benchmark tests skipped; set NLW_BENCHMARK=1 to run them";
    }
    else {
        diag "Running benchmark for medium groups; this may take a while.";
        _do_benchmark( 200, 5 );
    }
}

###############################################################################
# BENCHMARK: how long does it take to refresh 1 Group with 1000 Users?
# total records: 1001
benchmark_one_large_group: {
    unless ($ENV{NLW_BENCHMARK}) {
        diag "Large group benchmark tests skipped; set NLW_BENCHMARK=1 to run them";
    }
    else {
        diag "Running benchmark for large group; this may take a while.";
        _do_benchmark( 1, 1000 );
    }
}

exit;

sub _do_benchmark {
    my $groups = shift || 100;
    my $users  = shift || 10;
    
    my $group_dns = _build_ldifs(
        file      => 'eraseme.ldif',
        groups    => $groups,
        users_per => $users,
    );

    my $openldap = set_up_openldap( 'eraseme.ldif' );
    unlink 'eraseme.ldif';

    _add_ldap_groups_to_st( $group_dns );
    _refresh_groups();
    _cleanup_groups($group_dns);
}

sub _cleanup_groups {
    my $groups = shift;

    diag "Cleaning up groups";
    my $t = timeit( 1, sub {
        foreach my $dn ( @$groups ) {
            my $group = Socialtext::Group->GetGroup( driver_unique_id => $dn );

            map { Test::Socialtext::User->delete_recklessly( $_ ) }
                $group->users->all;

            Test::Socialtext::Group->delete_recklessly( $group );
        }
    });
    diag "... " . timestr( $t );
}

sub _refresh_groups {
    diag "Forcibly refreshing all groups";
    my $t = timeit(1, sub {
        Socialtext::LDAP::Operations->RefreshGroups( force => 1 );
    } );
    diag "... " . timestr($t);
}

sub _add_ldap_groups_to_st {
    my $groups = shift;

    diag "Adding groups to ST";
    my $t = timeit( 1, sub {
        foreach my $dn ( @$groups ) {
            Socialtext::Group->GetGroup( driver_unique_id => $dn );
        }
    });
    diag "... " . timestr( $t );
}

sub _build_ldifs {
    my %p = @_;

    diag "Creating $p{groups} Groups with $p{users_per} User in each";

    my @group_ldifs = ();
    my @user_ldifs  = ();
    my @group_dns   = ();
    foreach my $group_count ( 0..$p{groups} ) {
        my $group_dn = "cn=Group $group_count,dc=example,dc=com";
        my @user_dns = ();

        foreach my $user_count ( 0..$p{users_per} ) {
            my $sn = "$group_count-$user_count";
            my $dn = "cn=User $sn,dc=example,dc=com";
            push @user_dns, $dn;
            push @user_ldifs, _user_ldif( $dn, $sn );
        }
        push @group_dns, $group_dn;
        push @group_ldifs, _group_ldif( $group_count, $group_dn, @user_dns );
    }

    _write_ldif( $p{file}, [ @group_ldifs, @user_ldifs ] );

    return [ @group_dns ];
}

sub _write_ldif {
    my $file = shift;
    my $ldif = shift;

    diag "Writing benchmark file: $file";
    my $t = timeit( 1, sub {
            write_file( $file, @$ldif );
    } );

    diag "... " . timestr( $t );
}

sub _group_ldif {
    my $cn        = shift;
    my $dn        = shift;
    my @member_dn = @_;

    my $members = ( @member_dn ) ? join( "\nmember: ", @member_dn ) : '';

    return <<EOLDIF;
dn: $dn
objectClass: groupOfNames
cn: Group $cn
$members

EOLDIF
}

sub _user_ldif {
    my $dn = shift;
    my $sn = shift;

    return <<ENDLDIF;
dn: $dn
objectClass: inetOrgperson
mail: test-$sn\@ken.socialtext.net
gn: User
sn: $sn
cn: User $sn

ENDLDIF
}

exit;
