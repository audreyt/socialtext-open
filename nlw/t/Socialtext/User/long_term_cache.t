#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings FATAL => 'all';
use mocked 'Net::LDAP';
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext tests => 131;
use Socialtext::SQL qw(sql_execute sql_singlevalue);

fixtures( 'ldap_anonymous' );

use_ok 'Socialtext::User';
use_ok 'Socialtext::User::Base';
use_ok 'Socialtext::User::LDAP::Factory';

my @TEST_USERS = (
    { dn            => 'huh=auser,dc=example,dc=com',
      cn            => 'Onlyuse Once',
      authPassword  => 'abc123',
      gn            => 'Onlyuse',
      sn            => 'Once',
      mail          => 'justonce@example.com',
    },
    { dn            => 'huh=auser,dc=example,dc=com',
      cn            => 'Onlyuse Once',
      authPassword  => 'abc123',
      gn            => 'NewFirst',
      sn            => 'NewLast',
      mail          => 'justonce@example.com',
    },
    { dn            => 'huh=auser,dc=example,dc=com',
      cn            => 'Whynot Usetwice',
      authPassword  => 'qwe098',
      gn            => 'Whynot',
      sn            => 'Usetwice',
      mail          => 'twice@example.com',
    },
);

###############################################################################
# set up LDAP as a viable user factory (otherwise ST:User->new doesn't
# pull from LDAP)
my $appconfig = Socialtext::AppConfig->new();
my $user_factories = 'LDAP;Default';
$appconfig->set(user_factories => $user_factories);
$appconfig->write();
is $appconfig->user_factories, $user_factories,
    'Configured to use LDAP user factory';

###############################################################################
# create an LDAP factory to test with
my $factory = Socialtext::User::LDAP::Factory->new();
isa_ok $factory, 'Socialtext::User::LDAP::Factory';
my $driver_key = $factory->driver_key;

###############################################################################
# select a test user, and set up our mocked LDAP connection to return that
# to us on searches.
Net::LDAP->set_mock_behaviour(
    search_results => [ $TEST_USERS[0] ],
);
my $dn       = $TEST_USERS[0]{dn};
my $username = lc( $TEST_USERS[0]{cn} );    # stored internally as lower-case
my $email    = lc( $TEST_USERS[0]{mail} );  # stored internally as lower-case

###############################################################################
# TEST: make sure that test User does *NOT* exist in the DB yet
check_no_userid_yet: {
    ok !get_cache(driver_username => $username);
    ok !get_cache(driver_unique_id => $dn);
}

###############################################################################
# TEST: instantiate the user (which auto-vivifies him), and make sure that
# we've got the appropriate bits in the DB.
my $user;
my $user_id;
my $cached_at;
auto_vivification: {
    $user = Socialtext::User->new(username => $username);
    ok $user, '... found user by username';
    ok $user->user_id, '... got assigned a user_id';
    $user_id = $user->user_id;

    my $homunculus = $user->homunculus();
    isa_ok $homunculus, 'Socialtext::User::LDAP',
        '... auto-vivified LDAP homunculus';
    isa_ok $user->cached_at, 'DateTime',
        '... cached_at field is a DateTime object';
    ok $user->cached_at->is_finite, 
        '... cached_at is finite (not +/- infinity)';
}

###############################################################################
# TEST: check long-term cache to make sure it has the right stuff for this User
autovivify_cache_value: {
    my $cached = get_cache(driver_username => $username);
    ok $cached, "got a cached user";
    $cached_at = delete $cached->{cached_at};
    my $last_profile_update = delete $cached->{last_profile_update};
    is_deeply $cached, {
        user_id             => $user_id,
        driver_username     => $username,
        driver_key          => $driver_key,
        driver_unique_id    => $dn,
        email_address       => $email,
        first_name          => 'Onlyuse',
        middle_name         => '',
        last_name           => 'Once',
        display_name        => 'Onlyuse Once',
        password            => '*no-password*',
        is_profile_hidden   => '0',
        missing             => '0',
        private_external_id => undef,
    };

    # not strictly necessary, but a nice sanity check:
    $cached->{cached_at} = $cached_at;
    $cached->{last_profile_update} = $last_profile_update;
    my $cached2 = get_cache(user_id => $user_id);
    is_deeply $cached, $cached2, "cached copies are identical";
}

my %user_tests = (
    user_id          => $user_id,
    username         => $username,
    email_address    => $email,
    driver_unique_id => $dn
);

###############################################################################
# pretend that the LDAP user is removed from the LDAP directory; we should
# get back the *cached* user data (so long as the cache is valid);
Net::LDAP->set_mock_behaviour(
    search_results => [],
);

###############################################################################
# TEST: use the cached copy of the User if its still fresh; don't hit LDAP
ldap_user_comes_from_cache_if_fresh: {
    foreach my $key (sort keys %user_tests) {
        my $val = $user_tests{$key};
        my $cached_user = Socialtext::User->new($key => $val);
        ok $cached_user, "found user by $key, even when not in LDAP any longer";

        my $cached_homey = $cached_user->homunculus;
        isa_ok $cached_homey, 'Socialtext::User::LDAP',
            '... cached homunculus is LDAP';

        {
            # cached_at will likely differ by nanoseconds due to rounding and
            # the resolution of times in Pg; ignore it for the moment
            local $cached_user->{homunculus}{cached_at};
            local $user->{homunculus}{cached_at};
            $cached_user->{homunculus}{extra_attrs} = undef;
            is_deeply $user, $cached_user, '... matches original user';
        }

        is $cached_user->cached_at->epoch(),
           $user->cached_at->epoch(),
           '... cached_at roughly matches';

        is $cached_homey->driver_unique_id, $dn,
            '... cached homunculus has DN as ID';
    }
}

###############################################################################
# expire the cached LDAP user; we'll go back to LDAP and refresh our
# cached copy of the user based on the data we get back.
Net::LDAP->set_mock_behaviour(
    search_results => [ $TEST_USERS[1] ],
);

###############################################################################
# TEST: once expired, the User should be fetched from LDAP
expired_ldap_user_comes_from_ldap: {
    foreach my $key (sort keys %user_tests) {
        my $val = $user_tests{$key};
        reset_user($user_id);

        my $fresh_user = Socialtext::User->new($key => $val);
        ok $fresh_user, "found user by $key, even when not in LDAP any longer";
        user_fields_ok(1 => $fresh_user);
        db_cache_ok(1);
    }
}

###############################################################################
# delete the user from the LDAP store
Net::LDAP->set_mock_behaviour(
    search_results => [ ],
);

###############################################################################
# TEST: if User no longer exists in LDAP, they're a "Deleted User"
expired_ldap_user_is_Deleted_if_missing: {
    foreach my $key (sort keys %user_tests) {
        my $val = $user_tests{$key};
        reset_user($user_id);

        my $cached_user = Socialtext::User->new($key => $val);
        ok $cached_user,
            "found user by $key, even when expired and not in LDAP any longer";
        ok $cached_user->is_deleted(), '... and User is deleted';
    }
}

###############################################################################
# update the plan to user 2
Net::LDAP->set_mock_behaviour(
    search_results => [ $TEST_USERS[2] ],
);
$username   = lc( $TEST_USERS[2]{cn} );     # stored internally as lower-case
$email      = lc( $TEST_USERS[2]{mail} );   # stored internally as lower-case
%user_tests = (
    user_id          => $user_id,
    username         => $username,
    email_address    => $email,
    driver_unique_id => $dn
);

###############################################################################
# TEST: fetching User from LDAP is possible even if some of the data changes
expired_user_can_change_identity: {
    foreach my $key (sort keys %user_tests) {
        my $val = $user_tests{$key};
        reset_user($user_id);

        my $fresh_user = Socialtext::User->new($key => $val);
        ok $fresh_user, "found user by $key, even when $key changed";

        user_fields_ok(2 => $fresh_user);
        db_cache_ok(2);
    }
}

exit;

sub get_cache {
    my ($key, $val) = @_;
    my $sth = sql_execute("SELECT * FROM users WHERE $key = ?", $val);
    my $row = $sth->fetchrow_hashref();
    return $row;
}

sub reset_user {
    my $user_id = shift;
    sql_execute(q{
            UPDATE users 
            SET cached_at='-infinity'::timestamptz,
                first_name = ?,
                last_name = ?,
                email_address = ?,
                driver_username = ?,
                password = '*none*'
            WHERE user_id = ?
        }, 
        $TEST_USERS[0]{gn},
        $TEST_USERS[0]{sn},
        lc($TEST_USERS[0]{mail}),   # stored internally as lower-case
        lc($TEST_USERS[0]{cn}),     # stored internally as lower-case
        $user_id,
    );
}

sub db_cache_ok {
    my $user_num = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $cached = get_cache(user_id => $user_id);
    delete $cached->{cached_at};
    delete $cached->{last_profile_update};
    is_deeply $cached, {
        user_id             => $user_id,
        driver_key          => $driver_key,
        driver_username     => lc($TEST_USERS[$user_num]{cn}),      # stored internally as lower-case
        driver_unique_id    => $TEST_USERS[$user_num]{dn},
        email_address       => lc($TEST_USERS[$user_num]{mail}),    # stored internally as lower-case
        first_name          => $TEST_USERS[$user_num]{gn},
        middle_name         => '',
        last_name           => $TEST_USERS[$user_num]{sn},
        password            => '*no-password*',
        is_profile_hidden   => '0',
        display_name        => join(' ', @{ $TEST_USERS[$user_num] }{qw/gn sn/}),
        missing             => '0',
        private_external_id => undef,
    };
}

sub user_fields_ok {
    my $user_num = shift;
    my $new_user = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    is $new_user->user_id, $user_id, '... matches original user_id';
    is $new_user->username          => lc($TEST_USERS[$user_num]{cn});      # stored internally as lower-case
    is $new_user->email_address     => lc($TEST_USERS[$user_num]{mail});    # stored internally as lower-case
    is $new_user->first_name        => $TEST_USERS[$user_num]{gn};
    is $new_user->last_name         => $TEST_USERS[$user_num]{sn};

    my $new_homey = $new_user->homunculus;
    isa_ok $new_homey, 'Socialtext::User::LDAP', 
        '... homunculus is LDAP';
    is $new_homey->driver_unique_id, $dn, '... homunculus has DN as ID';

    ok $new_homey->cached_at->is_finite, '... cached time is finite';
    ok $new_homey->cached_at > $user->cached_at,
        '... cache time is newer than the original expected';
}
