#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 333;
use Socialtext::LDAP;
use Socialtext::LDAP::Base;
use Socialtext::User;
use Socialtext::User::LDAP::Factory;
use Time::HiRes ();
use Benchmark qw(timeit timestr);

###############################################################################
###############################################################################
### This is a bit of a hairy test, so lets explain what we're doing here...
###
### We've got both a "short-term, in memory cache" of User objects, which
### generally lives *only* for the lifetime of an HTTP request.  We also have
### a "long-term in DB cache" of User _data_.
###
### What we want to make sure of, is that when these two caches are enabled or
### disabled, that we get the right number of fetches to said caches based on
### the behaviour we're expecting to see.  This behaviour is dependant on the
### first run through priming/initializing the cache, and then all subsequent
### lookups coming from one of the two caches.  As such, we'll do multiple
### repetitions of each set of tests so that we know that we're exercising
### both sets of cases.
###############################################################################
###############################################################################
###############################################################################

###############################################################################
# Fixtures: db
#
# Need to have a DB running, but don't need anything else in it.
fixtures( 'db' );

###############################################################################
# REPETITIONS:      number of repetitions we're doing for all tests
# LOOKUP_FIELDS:    homunculus fields we're testing cache lookups with
#                   (matches the list of %ValidKeys from ST:U:Cache)
# LDAP_DELAY:       delay (in secs) that an LDAP request incurs (perf testing)
my $REPETITIONS = 3;
my @LOOKUP_FIELDS = qw(username email_address user_id driver_unique_id);
my $LDAP_DELAY = 0;

###############################################################################
# Bootstrap OpenLDAP, and fill it with our test users.
my $openldap;
bootstrap_openldap: {
    # fire up OpenLDAP
    $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP', 'bootstrapped OpenLDAP';

    # populate OpenLDAP with users
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'), 'added LDAP data; base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'), 'added LDAP data; people';
}

###############################################################################
# Initialization: vivify all the users we're testing with, so that we know
# that they already exist in our DB as user records.
my @USERS;
my $NUM_USERS;
init_vivify_all_users: {
    my @ldap_email_addresses = qw(
        john.doe@example.com
        jane.smith@example.com
        bubba.brain@example.com
        jim.smith@example.com
        jim.q.smith@example.com
    );
    foreach my $email (@ldap_email_addresses) {
        my $user = Socialtext::User->new( email_address => $email );
        isa_ok $user, 'Socialtext::User', "got user w/email: $email";
        isa_ok $user->homunculus, 'Socialtext::User::LDAP', "and they're an LDAP user";
        push @USERS, $user;
    }
    $NUM_USERS = @USERS;
}

###############################################################################
# Over-ride a few things so we can provide some instrumentation counters.
{
    my %stats = (
        ldap_searches => 0,
        ldap_cache_checks => 0,
    );

    ###########################################################################
    # Number of searches done against LDAP stores.
    sub ldap_searches {
        return $stats{ldap_searches};
    }
    override_ldap_search: {
        no warnings 'redefine';
        my $old = \&Socialtext::LDAP::Base::search;
        *Socialtext::LDAP::Base::search = sub {
            $stats{ldap_searches}++;
            Time::HiRes::sleep( $LDAP_DELAY );
            goto $old;
        };
    }

    ###########################################################################
    # Number of checks on the long-term LDAP user cache.
    sub ldap_cache_checks {
        return $stats{ldap_cache_checks};
    }
    override_ldap_cache_check: {
        no warnings 'redefine';
        my $old = \&Socialtext::User::LDAP::Factory::db_cache_ttl;
        *Socialtext::User::LDAP::Factory::db_cache_ttl = sub {
            $stats{ldap_cache_checks}++;
            goto $old;
        };
    }

    ###########################################################################
    # Number of checks on the short-term user cache.
    sub user_cache_checks {
        return $Socialtext::User::Cache::stats{fetch};
    };

    ###########################################################################
    # Reset all of the instrumentation counters, and expire all users.
    sub reset_counts {
        map { $stats{$_} = 0 } keys %stats;
        Socialtext::User::Cache->ClearStats();
    }

}

###############################################################################
# Method to expire all of the User records we're testing against, so that we
# know that their long-term cache entries are stale.
sub expire_users {
    map { $_->homunculus->expire } @USERS;
}

###############################################################################
# Methods to enable/disable the short/long term caches.
sub enable_short_term_cache {
    $Socialtext::User::Cache::Enabled = shift;
}

sub enable_long_term_cache {
    $Socialtext::User::LDAP::Factory::CacheEnabled = shift;
}

###############################################################################
# Method to lookup all of the users, using the specified field.  Then checks
# to make sure that we actually found the right number of users
sub perform_user_lookup {
    my $field = shift;
    my $found = 0;
    foreach my $user (@USERS) {
        my $lookup = Socialtext::User->new( $field, $user->homunculus->$field );
        if ($lookup && (ref($lookup->homunculus) eq 'Socialtext::User::LDAP')) {
            $found++;
        }
    }
    is $found, $NUM_USERS, "... found all of the users in LDAP";
}

###############################################################################
# TEST: both short+long term caches disabled.
#
# Expectation is that *all* user lookups would go straight through to the LDAP
# servers.  Both caches are disabled, so we shouldn't even be checking in them
# to see if we've got matching Users.
short_disabled_long_disabled: {
    diag "TEST: both short-term and long-term caches disabled";

    # turn caches on/off
    enable_short_term_cache( 0 );
    enable_long_term_cache( 0 );

    # all user lookups should go *straight* through to LDAP
    foreach my $field (@LOOKUP_FIELDS) {
        expire_users();

        foreach my $repetition (0 .. $REPETITIONS) {
            ok 1, "$field, repetition $repetition";

            reset_counts();
            perform_user_lookup($field);

            is ldap_searches(), $NUM_USERS, "... had to dip to LDAP for all users";
            is ldap_cache_checks(), 0, "... never looked in long-term cache; disabled";
            is user_cache_checks(), 0, "... never looked in short-term cache; disabled";
        }
    }
}

###############################################################################
# TEST: short-term cache disabled, long-term cache enabled
#
# Expectation is that the first set of lookups would go straight through to
# LDAP, and that all subsequent lookups are served from the long-term cache.
# Short-term cache is disabled, though, and shouldn't *ever* have any lookups
# done against it.
short_disabled_long_enabled: {
    diag "TEST: short-term cache disabled, long-term cache enabled";

    # turn caches on/off
    enable_short_term_cache( 0 );
    enable_long_term_cache( 1 );

    # first user lookup should go through to LDAP, all others should get
    # served from the long-term cache.
    foreach my $field (@LOOKUP_FIELDS) {
        expire_users();

        foreach my $repetition (0 .. $REPETITIONS) {
            ok 1, "$field, repetition $repetition";

            reset_counts();
            perform_user_lookup($field);

            if ($repetition == 0) {
                # first time through, we go to LDAP
                is ldap_searches(), $NUM_USERS, "... had to dip to LDAP for all users";
                is ldap_cache_checks(), $NUM_USERS, "... looked in long-term cache for all users";
                is user_cache_checks(), 0, "... never looked in short-term cache; disabled";
            }
            else {
                # all other times, we get out of long-term cache
                is ldap_searches(), 0, "... no LDAP searches performed";
                is ldap_cache_checks(), $NUM_USERS, "... looked in long-term cache for all users";
                is user_cache_checks(), 0, "... never looked in short-term cache; disabled";
            }
        }
    }
}

###############################################################################
# TEST: short-term cache enabled, long-term cache disabled
#
# Expectation is that the first set of lookups would go straight through to
# LDAP, and that all subsequent lookups are served from the short-term cache.
# Long-term cache is disabled, though, and shouldn't *ever* have any lookups
# done against it (even when we're doing the lookups against the LDAP server).
short_enabled_long_disabled: {
    diag "TEST: short-term cache enabled, long-term cache disabled";

    # turn caches on/off
    enable_short_term_cache( 1 );
    enable_long_term_cache( 0 );

    # first user lookup should go through to LDAP, all others should get
    # served from the short-term cache.
    foreach my $field (@LOOKUP_FIELDS) {
        expire_users();

        foreach my $repetition (0 .. $REPETITIONS) {
            ok 1, "$field, repetition $repetition";

            reset_counts();
            perform_user_lookup($field);

            if ($repetition == 0) {
                # first time through, we go to LDAP
                is ldap_searches(), $NUM_USERS, "... had to dip to LDAP for all users";
                is ldap_cache_checks(), 0, "... never looked in long-term cache; disabled";
                is user_cache_checks(), $NUM_USERS, "... looked in short-term cache for all users";
            }
            else {
                # all other times, we get out of short-term cache
                is ldap_searches(), 0, "... no LDAP searches performed";
                is ldap_cache_checks(), 0, "... never looked in long-term cache; disabled";
                is user_cache_checks(), $NUM_USERS, "... looked in short-term cache for all users";
            }
        }
    }
}

###############################################################################
# TEST: both short+long term caches enabled.
#
# Expectation is that the first set of lookups would go straight through to
# LDAP, and that all subsequent lookups are served from the short-term cache.
# Long-term cache is enabled, and on the first set of lookups we'll be
# checking the cache for entries (but won't find any, thus hitting the LDAP
# server instead).
short_enabled_long_enabled: {
    diag "TEST: both short-term and long-term caches enabled";

    # turn caches on/off
    enable_short_term_cache( 1 );
    enable_long_term_cache( 1 );

    # first user lookups should go through to LDAP, after first doing a lookup
    # on the long-term cache.  All other lookups should get served from the
    # short-term cache.
    foreach my $field (@LOOKUP_FIELDS) {
        expire_users();

        foreach my $repetition (0 .. $REPETITIONS) {
            ok 1, "$field, repetition $repetition";

            reset_counts();
            perform_user_lookup($field);

            if ($repetition == 0) {
                # first time through, we go to LDAP
                is ldap_searches(), $NUM_USERS, "... had to dip to LDAP for all users";
                is ldap_cache_checks(), $NUM_USERS, "... looked in long-term cache for all users";
                is user_cache_checks(), $NUM_USERS, "... looked in short-term cache for all users";
            }
            else {
                # all other times, we get out of short-term cache
                is ldap_searches(), 0, "... no LDAP searches performed";
                is ldap_cache_checks(), 0, "... never looked in long-term cache; disabled";
                is user_cache_checks(), $NUM_USERS, "... looked in short-term cache for all users";
            }
        }
    }
}

###############################################################################
# BENCHMARK: Run a test scenario against various cases of the caches being
# enabled/disabled, to demonstrate what the performance improvements are.
#
# For the purpose of this benchmark we're going to confabulate the following
# scenario.... a series of simulated HTTP requests, after each of which the
# short-term cache is flushed.  During each HTTP request, a number of user
# lookups are going to be performed to simulate things such as user wafls,
# authen, etc.
benchmark_demonstration: {
    unless ($ENV{NLW_BENCHMARK}) {
        diag "Benchmark tests skipped; set NLW_BENCHMARK=1 to run them";
    }
    else {
        diag "Benchmark tests running; this may take a while...";
        sub run_scenario {
            my %p                   = @_;
            my $num_http_requests   = $p{requests} || 20;
            my $lookups_per_request = $p{lookups}  || 20;
            my $ldap_delay          = $p{delay}    || 0;
            my $long_cache_enabled  = $p{long}     || 0;
            my $short_cache_enabled = $p{short}    || 0;

            # set the LDAP delay
            $LDAP_DELAY = $p{delay};

            # enable/disable caches
            enable_short_term_cache($short_cache_enabled);
            enable_long_term_cache($long_cache_enabled);

            # ensure that caches are empty when we start
            expire_users();

            # build a closure to run the scenario
            my $scenario = sub {
                # fire off a single simulated request, doing the lookup using a
                # field that's *not* the best-case scenario (which is user_id);
                # we'll use "email_address" instead (for no reason other than its
                # not the best-case).

                foreach my $lookup (0 .. $lookups_per_request) {
                    my $to_find = $USERS[ $lookup % $NUM_USERS ];
                    my $found   = Socialtext::User->new(email_address => $to_find->homunculus->email_address);
                    die "failed to find user in perf test" unless $found;
                }
                Socialtext::Cache->clear();
            };

            # run the scenario.
            diag "... scenario: " . join(' ', map { "$_=$p{$_}" } sort keys %p);
            my $t = timeit($num_http_requests, $scenario);
            diag "... ... " . timestr($t);
        }

        foreach my $delay (qw(10 25 50)) {
            my $delay_ms = $delay / 1000;
            foreach my $lookups (qw(10 20 50)) {
                diag "\nLDAP delay ${delay}ms, $lookups lookups per request";
                run_scenario( short=>0, long=>0, lookups=>$lookups, delay=>$delay_ms );
                run_scenario( short=>0, long=>1, lookups=>$lookups, delay=>$delay_ms );
                run_scenario( short=>1, long=>0, lookups=>$lookups, delay=>$delay_ms );
                run_scenario( short=>1, long=>1, lookups=>$lookups, delay=>$delay_ms );
            }
        }
    }
}
