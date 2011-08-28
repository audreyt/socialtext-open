#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 46;
use Socialtext::LDAP::Operations;
use File::Slurp qw(write_file);
use Benchmark qw(timeit timestr);

###############################################################################
# FIXTURE:  db
#
# Need to have the DB around, but don't care what's in it.
fixtures(qw( db ));

###############################################################################
# ERASE any existing LDAP config, so it doesn't pollute this test suite
unlink Socialtext::LDAP::Config->config_filename();

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
our $NUM_TEST_USERS = 6;    # number of users in 'people.ldif'

###############################################################################
# TEST: Load successfully
test_load_successfully: {
    my $ldap = set_up_openldap();
    clear_log();

    my $count_before = Socialtext::User->Count();

    # load Users, make sure its successful and that its logged everything
    my $rc = Socialtext::LDAP::Operations->LoadUsers();
    is $rc, $NUM_TEST_USERS, 'loaded correct number of LDAP Users';
    logged_like 'info', qr/found $NUM_TEST_USERS LDAP users to load/,
        '... logged number of LDAP Users found';

    logged_like 'info', qr/loading: john.doe/,    '... added John Doe';
    logged_like 'info', qr/loading: jane.smith/,  '... added Jane Smith';
    logged_like 'info', qr/loading: bubba.brain/, '... added Bubba Brain';
    logged_like 'info', qr/loading: jim.smith/,   '... added Jim Smith';
    logged_like 'info', qr/loading: jim.q.smith/, '... added Jim Q Smith';
    logged_like 'info', qr/loading: ray.parker/,  '... added Ray Parker';

    logged_like 'info', qr/loaded $NUM_TEST_USERS out of $NUM_TEST_USERS total/,
        '... logged success count';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before+$NUM_TEST_USERS,
        '... total User count matches expectation';
}

###############################################################################
# TEST: if we've got *NO* LDAP configurations, load doesn't choke.
test_no_ldap_configurations: {
    clear_log();

    # remove any LDAP config file that might be present
    my $cfg_file = Socialtext::LDAP::Config->config_filename();
    unlink $cfg_file;
    ok !-e $cfg_file, 'no LDAP config present';

    # load Users, make sure it finds nobody to load
    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers();
    ok !$rc, 'load operation fails';
    logged_like 'info', qr/found 0 LDAP users to load/,
        '... because NO LDAP Users found to load';

    my $count_after = Socialtext::User->Count();
    is $count_before, $count_after, '... and no Users were loaded';
}

###############################################################################
# TEST: LDAP configuration missing filter; refuses to load Users
test_ldap_config_missing_filter: {
    my $ldap = set_up_openldap();
    clear_log();

    # clear the filter in the LDAP config, and make sure it clears properly
    $ldap->ldap_config->filter(undef);
    $ldap->add_to_ldap_config();

    my $config = Socialtext::LDAP::Config->load();
    my $filter = $config->filter();
    ok !$filter, 'LDAP config contains *NO* filter';

    # load Users, make sure it fails
    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers();
    ok !$rc, 'load operation fails';
    logged_like 'error', qr/no LDAP filter in config/,
        '... load fails due to lack of LDAP filter';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before, '... and no Users were loaded';
}

###############################################################################
# TEST: LDAP User contains invalid/bogus data; skips that User
test_user_fails_data_validation: {
    my $ldap = set_up_openldap();
    clear_log();

    # create a test User that has an invalid e-mail address
    $ldap->add(
        'cn=Invalid Email,dc=example,dc=com',
        objectClass  => 'inetOrgPerson',
        cn           => 'Invalid Email',
        gn           => 'Invalid',
        sn           => 'Email',
        mail         => 'invalid-email',
        userPassword => 'abc123',
    );

    # load Users, make sure we tried this user, and that he failed validation
    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers();
    is $rc, $NUM_TEST_USERS, 'loaded correct number of LDAP Users';

    my $total_users = $NUM_TEST_USERS + 1;
    logged_like 'info', qr/found $total_users LDAP users to load/,
        '... logged number of LDAP Users found (including invalid user)';

    logged_like 'info', qr/loading: invalid-email/,
        '... tried adding invalid User';

    logged_like 'error', qr/"invalid-email" is not a valid email address/,
        '... which failed due to invalid e-mail address';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before+$NUM_TEST_USERS,
        '... total User count matches expectation';
}

###############################################################################
# TEST: LDAP User missing e-mail address; isn't considered valid for loading
test_user_without_email_isnt_considered: {
    my $ldap = set_up_openldap();
    clear_log();

    # switch LDAP config around so that the "email address" attribute is going
    # to be blank for all of our test Users.
    $ldap->ldap_config->{attr_map}{email_address} = 'title';
    $ldap->add_to_ldap_config();

    my $config = Socialtext::LDAP::Config->load();
    my $attr   = $config->{attr_map}{email_address};
    is $attr, 'title', 'switched e-mail address attribute';

    # load Users, make sure the above User was *not* considered for load
    # - if the count matches the regular number of test Users, he wasn't
    #   considered for the load
    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers();
    ok !$rc, 'load operation fails';
    logged_like 'info', qr/found 0 LDAP users to load/,
        '... because NO LDAP Users found to load';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before, '... and no Users were loaded';
}

###############################################################################
# TEST: Dry-run; finds Users, but doesn't load any of them.
test_dry_run: {
    my $ldap = set_up_openldap();
    clear_log();

    # load Users, make sure count before+after is the same
    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers(dryrun => 1);
    ok !$rc, 'did not load any LDAP Users';

    logged_like 'info', qr/found $NUM_TEST_USERS LDAP users to load/,
        '... logged number of LDAP Users found';

    logged_like 'info', qr/found: john.doe/,    '... found John Doe';
    logged_like 'info', qr/found: jane.smith/,  '... found Jane Smith';
    logged_like 'info', qr/found: bubba.brain/, '... found Bubba Brain';
    logged_like 'info', qr/found: jim.smith/,   '... found Jim Smith';
    logged_like 'info', qr/found: jim.q.smith/, '... found Jim Q Smith';
    logged_like 'info', qr/found: ray.parker/,  '... found Ray Parker';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before,
        '... and *none* of those Users were actually added to the system';
}

###############################################################################
# TEST: Load *single* User, by e-mail address
test_load_one_user_via_email: {
    my $ldap = set_up_openldap();
    clear_log();

    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers(
        email => 'john.doe@example.com',
    );
    is $rc, 1, 'loaded single LDAP User, by e-mail address';
    logged_like 'info', qr/found 1 LDAP users to load/,
        '... logged number of LDAP Users found';

    logged_like 'info', qr/loading: john.doe/,    '... added John Doe';
    logged_like 'info', qr/loaded 1 out of 1 total/, '... logged success count';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before+1, '... new User count matches expectation';
}

###############################################################################
# TEST: Load *single* User, by username
test_load_one_user_via_username: {
    my $ldap = set_up_openldap();
    clear_log();

    my $count_before = Socialtext::User->Count();

    my $rc = Socialtext::LDAP::Operations->LoadUsers(
        username => 'Jane Smith',
    );
    is $rc, 1, 'loaded single LDAP User, by username';
    logged_like 'info', qr/found 1 LDAP users to load/,
        '... logged number of LDAP Users found';

    logged_like 'info', qr/loading: jane.smith/,    '... added Jane Smith';
    logged_like 'info', qr/loaded 1 out of 1 total/, '... logged success count';

    my $count_after = Socialtext::User->Count();
    is $count_after, $count_before+1, '... new User count matches expectation';
}

###############################################################################
# BENCHMARK: how long does it take to load ~1000 users?
benchmark_load: {
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
objectClass: inetOrgPerson
cn: User $count
gn: User
sn: $count
mail: $email
userPassword: abc123

ENDLDIF
        }

        # add all of the users to OpenLDAP
        my $openldap = set_up_openldap();
        diag "adding $BENCHMARK_USERS users to OpenLDAP";
        $t = timeit(1, sub {
            my $ldif_file = 'eraseme.ldif';
            write_file( $ldif_file, @ldif );
            $openldap->add_ldif( $ldif_file );
            unlink $ldif_file;
        } );
        diag "... " . timestr($t);

        # load all of the Users into ST, with the cache disabled
        diag "loading $BENCHMARK_USERS into ST, cache disabled";
        $t = timeit(1, sub {
            local $Socialtext::LDAP::CacheEnabled = 0;
            Socialtext::Cache->clear();
            Socialtext::LDAP::Operations->LoadUsers();
        } );
        diag "... " . timestr($t);

        # remove the test Users between loads
        diag "cleaning up $BENCHMARK_USERS users";
        $t = timeit(1, sub {
            foreach my $email (@emails) {
                my $user = Socialtext::User->new(email_address => $email);
                Test::Socialtext::User->delete_recklessly($user);
            }
        } );
        diag "... " . timestr($t);

        # load all of the Users into ST, with the cache enabled
        diag "loading $BENCHMARK_USERS into ST, cache enabled";
        $t = timeit(1, sub {
            Socialtext::Cache->clear();
            Socialtext::LDAP::Operations->LoadUsers();
        } );
        diag "... " . timestr($t);

        # cleanup; remove all our users so that the test harness doesn't spit
        # out gobs of stuff on the screen
        diag "cleaning up $BENCHMARK_USERS users";
        $t = timeit(1, sub {
            foreach my $email (@emails) {
                my $user = Socialtext::User->new(email_address => $email);
                Test::Socialtext::User->delete_recklessly($user);
            }
        } );
        diag "... " . timestr($t);
    }
}
