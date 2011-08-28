#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 69;
use Test::Socialtext::User;
use File::Slurp qw(write_file);
use Benchmark qw(timeit timestr);
use Socialtext::SQL qw(:exec);
use Socialtext::Date;
use Socialtext::LDAP::Operations;

###############################################################################
# FIXTURE: db
#
# Need to have the DB around, but don't care whats in it.
fixtures( 'db' );

###############################################################################
# Sets up OpenLDAP, adds some test data, and adds the OpenLDAP server to our
# list of user factories.
sub set_up_openldap {

    for my $user (Socialtext::User->All->all()) {
        next if $user->is_system_created;
        Test::Socialtext::User->delete_recklessly($user);
    }

    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    $openldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $openldap->add_ldif('t/test-data/ldap/people.ldif');
    return $openldap;
}

###############################################################################
# TEST: if we've got *NO* LDAP users, refresh doesn't choke.
test_no_ldap_users: {
    Socialtext::LDAP::Operations->RefreshUsers();
    logged_like 'info', qr/found 0 LDAP users/, '... no LDAP users present';
}

###############################################################################
# TEST: have LDAP users, but they're all fresh; not refreshed again.
test_ldap_users_all_fresh: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user';

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # refresh LDAP users
    Socialtext::LDAP::Operations->RefreshUsers();
    logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';

    # get the refreshed LDAP user record
    my $refreshed_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $refreshed_user, 'Socialtext::User', 'refreshed LDAP user';

    my $refreshed_homey = $refreshed_user->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::User::LDAP', 'refreshed LDAP homunculus';

    # make sure that we've got different copies of the User object, *but* that
    # they were both cached at the same time (e.g. we didn't just refresh the
    # user).
    isnt $ldap_homey, $refreshed_homey, 'user objects are different';
    is $refreshed_homey->cached_at->hires_epoch,
        $ldap_homey->cached_at->hires_epoch,
        'user was not refreshed; was already fresh';
}

###############################################################################
# TEST: have LDAP users, some of which have never been cached; users that have
# never been cached are refreshed.
#
# We *also* test here to make sure that the first_name/last_name/username are
# refreshed properly.  This is then skipped in subsequent tests (as we've
# already tested for that condition here).
test_refresh_stale_users: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user';

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # update the DB with new info, so we'll be able to verify that the user
    # did in fact get his/her data refreshed from LDAP again.
    sql_execute( qq{
        UPDATE users
           SET first_name='bogus_first',
               last_name='bogus_last',
               driver_username='bogus_username'
         WHERE driver_unique_id=?
        }, $ldap_homey->driver_unique_id );
    my $bogus_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    is $bogus_user->first_name, 'bogus_first', 'set bogus data to first_name';
    is $bogus_user->last_name, 'bogus_last', 'set bogus data to last_name';
    is $bogus_user->username, 'bogus_username', 'set bogus data to username';

    # expire the user, so that they'll get refreshed
    $ldap_homey->expire();

    # refresh LDAP users
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers();
        logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # get the refreshed LDAP user record
    my $refreshed_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $refreshed_user, 'Socialtext::User', 'refreshed LDAP user';

    my $refreshed_homey = $refreshed_user->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::User::LDAP', 'refreshed LDAP homunculus';

    # make sure the user *was* refreshed by the call to RefreshUsers()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';

    # make sure that the bogus data we set into the user was over-written by
    # the refresh
    isnt $ldap_homey->first_name, 'bogus_first', '... first_name was refreshed';
    isnt $ldap_homey->last_name, 'bogus_last', '... last_name was refreshed';
    isnt $ldap_homey->username, 'bogus_username', '... username was refreshed';
}

###############################################################################
# TEST: have LDAP users, force the refresh; *all* users are refreshed
# regardless of whether they're fresh/stale.
test_force_refresh: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user';

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # refresh LDAP users
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers(force => 1);
        logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # get the refreshed LDAP user record
    my $refreshed_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $refreshed_user, 'Socialtext::User', 'refreshed LDAP user';

    my $refreshed_homey = $refreshed_user->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::User::LDAP', 'refreshed LDAP homunculus';

    # make sure the user *was* refreshed by RefreshUsers()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';
}

###############################################################################
# TEST: refresh a *single* LDAP User, by e-mail address
refresh_single_user_via_email: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    # add some LDAP Users to our DB cache
    my $ldap_user  = Socialtext::User->new(email_address => 'john.doe@example.com');
    my $ldap_homey = $ldap_user->homunculus;

    my $other_user  = Socialtext::User->new(email_address => 'jane.smith@example.com');
    my $other_homey = $other_user->homunculus;

    # refresh *one* LDAP User
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers(
            force => 1,
            email => $ldap_user->email_address,
        );
        logged_like 'info', qr/found 1 LDAP users/,
            'one LDAP user refreshed, by e-mail address';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # VERIFY: User was refreshed by RefreshUsers()
    my $refreshed_user  = Socialtext::User->new(email_address => 'john.doe@example.com');
    my $refreshed_homey = $refreshed_user->homunculus;

    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';

    # VERIFY: Other User was *not* refreshed
    $refreshed_user  = Socialtext::User->new(email_address => 'jane.smith@example.com');
    $refreshed_homey = $refreshed_user->homunculus;

    $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at < $time_before_refresh->hires_epoch(), 'other user was NOT refreshed';
}

###############################################################################
# TEST: refresh a *single* LDAP User, by username
refresh_single_user_via_username: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    # add some LDAP Users to our DB cache
    my $ldap_user  = Socialtext::User->new(email_address => 'john.doe@example.com');
    my $ldap_homey = $ldap_user->homunculus;

    my $other_user  = Socialtext::User->new(email_address => 'jane.smith@example.com');
    my $other_homey = $other_user->homunculus;

    # refresh *one* LDAP User, by Username
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers(
            force    => 1,
            username => 'John Doe',
        );
        logged_like 'info', qr/found 1 LDAP users/,
            'one LDAP user refreshed, by username';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # VERIFY: User was refreshed by RefreshUsers()
    my $refreshed_user  = Socialtext::User->new(email_address => 'john.doe@example.com');
    my $refreshed_homey = $refreshed_user->homunculus;

    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';

    # VERIFY: Other User was *not* refreshed
    $refreshed_user  = Socialtext::User->new(email_address => 'jane.smith@example.com');
    $refreshed_homey = $refreshed_user->homunculus;

    $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at < $time_before_refresh->hires_epoch(), 'other user was NOT refreshed';
}

###############################################################################
# TEST: refresh missing LDAP Users.
refresh_missing_ldap_users: {
    my $ldap = set_up_openldap();

    # load a User from LDAP
    my $ldap_user = Socialtext::User->new(email_address => 'john.doe@example.com');
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user';

    # refresh User; should still be "found"
    {
        Socialtext::LDAP::Operations->RefreshUsers(force => 1);
        my $refreshed = Socialtext::User->new(email_address => 'john.doe@example.com');
        ok !$refreshed->missing, '... not missing after refresh';
    }

    # remove User from LDAP
    my $dn   = $ldap_user->driver_unique_id;
    my $conn = Socialtext::LDAP->new();
    my $mesg = $conn->{ldap}->delete($dn);
    ok !$mesg->is_error, '... removed User from LDAP';

    # refresh User; should be "missing"
    {
        Socialtext::LDAP::Operations->RefreshUsers(force => 1);
        my $refreshed = Socialtext::User->new(email_address => 'john.doe@example.com');
        ok $refreshed->missing, '... now missing';
    }

    # cleanup; don't want to pollute other tests
    Test::Socialtext::User->delete_recklessly($ldap_user);
}

###############################################################################
# TEST: first name is missing; should run clean, and set first name to ''
test_ldap_missing_first_name: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    my $user_dn = 'cn=John Doe,dc=example,dc=com';

    # modify the LDAP config, so that the "first_name" field gets mapped to an
    # LDAP attribute that could be blank/empty.
    $ldap->ldap_config->{attr_map}{first_name} = 'title';
    $ldap->add_to_ldap_config();

    # modify the test User record in LDAP so that it *has* a first name
    my $rc = $ldap->modify( $user_dn, add => { title => 'TestFirst' }  );
    ok $rc, 'modified LDAP user, giving them a first_name';

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user missing first name';

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # make sure the first name *was* the one we set up for the test
    is $ldap_homey->first_name, 'TestFirst', '... with initial dummy first name';

    # modify the test User record in LDAP, clearing their first name
    $rc = $ldap->modify( $user_dn, delete => [qw(title)] );
    ok $rc, 'modified LDAP user, clearing their first_name';

    # expire the user, so that they'll get refreshed
    $ldap_homey->expire();

    # refresh LDAP users
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers();
        logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # get the refreshed LDAP user record
    my $refreshed_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $refreshed_user, 'Socialtext::User', 'refreshed LDAP user';

    my $refreshed_homey = $refreshed_user->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::User::LDAP', 'refreshed LDAP homunculus';

    # make sure the user *was* refreshed by RefreshUsers()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';

    # make sure that the User now has a blank/empty first name
    is $refreshed_homey->first_name, '', '... first_name is blank/empty';
}

###############################################################################
# TEST: last name is missing; should run clean, and set last name to ''
test_ldap_missing_last_name: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    my $user_dn = 'cn=John Doe,dc=example,dc=com';

    # modify the LDAP config, so that the "last_name" field gets mapped to an
    # LDAP attribute that could be blank/empty.
    $ldap->ldap_config->{attr_map}{last_name} = 'title';
    $ldap->add_to_ldap_config();

    # modify the test User record in LDAP so that it *has* a last name
    my $rc = $ldap->modify( $user_dn, add => { title => 'TestLast' } );
    ok $rc, 'modified LDAP user, giving them a last_name';

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user missing last name';

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # make sure the last name *was* the one we set up for the test
    is $ldap_homey->last_name, 'TestLast', '... with initial dummy last name';

    # modify the test User record in LDAP, clearing their last name
    $rc = $ldap->modify( $user_dn, delete => [qw(title)] );
    ok $rc, 'modified LDAP user, clearing their last_name';

    # expire the user, so that they'll get refreshed
    $ldap_homey->expire();

    # refresh LDAP users
    my $time_before_refresh = Socialtext::Date->now(hires=>1);
    {
        Socialtext::LDAP::Operations->RefreshUsers();
        logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';
    }
    my $time_after_refresh = Socialtext::Date->now(hires=>1);

    # get the refreshed LDAP user record
    my $refreshed_user = Socialtext::User->new( email_address => 'john.doe@example.com' );
    isa_ok $refreshed_user, 'Socialtext::User', 'refreshed LDAP user';

    my $refreshed_homey = $refreshed_user->homunculus;
    isa_ok $refreshed_homey, 'Socialtext::User::LDAP', 'refreshed LDAP homunculus';

    # make sure the user *was* refreshed by RefreshUsers()
    my $refreshed_at = $refreshed_homey->cached_at->hires_epoch();
    ok $refreshed_at > $time_before_refresh->hires_epoch(), 'user was refreshed';
    ok $refreshed_at < $time_after_refresh->hires_epoch(), '... by RefreshUsers()';

    # make sure that the User now has a blank/empty last name
    is $refreshed_homey->last_name, '', '... last_name is blank/empty';
}

###############################################################################
# TEST: e-mail address is missing; should warn about error, leave DB record
# untouched, and continue to run.
test_ldap_missing_email_address: {
    my $guard = Test::Socialtext::User->snapshot();
    my $ldap  = set_up_openldap();

    my $user_dn = 'cn=John Doe,dc=example,dc=com';

    # modify the LDAP config, so that the "email_address" field gets mapped to
    # an LDAP attribute that could be blank/empty.
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    # modify the test User record in LDAP so that it *has* an email address
    my $rc = $ldap->modify( $user_dn, add => { title => 'john.doe@example.com' } );
    ok $rc, 'modified LDAP user, giving them an email_address';

    # add an LDAP user to our DB cache
    my $ldap_user = Socialtext::User->new( username => 'John Doe' );
    isa_ok $ldap_user, 'Socialtext::User', 'LDAP user missing email address';
    my $username  = $ldap_user->username();

    my $ldap_homey = $ldap_user->homunculus;
    isa_ok $ldap_homey, 'Socialtext::User::LDAP', 'LDAP homunculus';

    # modify the test User record in LDAP, clearing their email address
    $rc = $ldap->modify( $user_dn, delete => [qw(title)] );
    ok $rc, 'cleared the users email address in LDAP';

    # expire the user, so that they'll get refreshed
    $ldap_homey->expire();

    # refresh LDAP users
    Socialtext::LDAP::Operations->RefreshUsers();
    logged_like 'info', qr/found 1 LDAP users/, 'one LDAP user present';
    logged_like 'warning', qr/Unable to refresh LDAP user '$username'/, '... unable to refresh the LDAP user';
    logged_like 'warning', qr/Email address is a required field/, '... LDAP user is missing e-mail address';
}

###############################################################################
# BENCHMARK: how long does it take to refresh ~1000 users?
benchmark_refresh: {
    my $BENCHMARK_USERS = 1000;

    unless ($ENV{NLW_BENCHMARK}) {
        diag "Benchmark tests skipped; set NLW_BENCHMARK=1 to run them";
    }
    else {
        diag "Benchmark tests running; this may take a while...";
        my $t;

        # build up a set of users to use for the benchmark
        my @ldif;
        my @emails;
        foreach my $count (0 .. $BENCHMARK_USERS) {
            my $email = "test-$count\@ken.socialtext.net";
            push @emails, $email;
            push @ldif, <<ENDLDIF;
dn: cn=User $count,dc=example,dc=com
objectClass: inetOrgperson
cn: User $count
gn: User
sn: $count
mail: $email
userPassword: abc123

ENDLDIF
        }

        # add all of the users to OpenLDAP
        my $openldap  = set_up_openldap();
        diag "adding $BENCHMARK_USERS users to OpenLDAP";
        $t = timeit(1, sub {
            my $ldif_file = 'eraseme.ldif';
            write_file( $ldif_file, @ldif );
            $openldap->add_ldif( $ldif_file );
            unlink $ldif_file;
        } );
        diag "... " . timestr($t);

        # add all of the users to our DB.
        #
        # Cheat a bit and re-use our LDAP connection, though, so that we don't
        # have to re-connect for every single one of the test users.
        #
        # NOTE: we re-load the LDAP config so that we're not asking the
        # bootstrapper to *re-generate* the config (it'll create a new id each
        # time we ask it for the config).
        diag "adding $BENCHMARK_USERS users to ST";
        $t = timeit(1, sub {
            my $config  = Socialtext::LDAP::Config->load();
            my $ldap_id = $config->id();
            my $factory = Socialtext::User::LDAP::Factory->new( $ldap_id );
            foreach my $email (@emails) {
                $factory->GetUser( email_address => $email );
            }
        } );
        diag "... " . timestr($t);

        # refresh all of the users
        diag "refreshing $BENCHMARK_USERS users";
        $t = timeit(1, sub {
            Socialtext::LDAP::Operations->RefreshUsers(force => 1);
        } );
        diag "... " . timestr($t);

        # cleanup; remove all our users so that the test harness doesn't spit
        # out gobs of stuff on the screen
        diag "cleaning up $BENCHMARK_USERS users";
        $t = timeit(1, sub {
            foreach my $email (@emails) {
                my $user = Socialtext::User->new( email_address => $email );
                Test::Socialtext::User->delete_recklessly($user);
            }
        } );
        diag "... " . timestr($t);
    }
}
