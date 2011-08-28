#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 27;
use Socialtext::SQL qw(:exec :time);
use Test::Socialtext::User;

fixtures(qw( db ));

###############################################################################
sub bootstrap_openldap {
    my $ldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    $ldap->add_ldif('t/test-data/ldap/base_dn.ldif');
    $ldap->add_ldif('t/test-data/ldap/people.ldif');

    # Set explicit "ttl" and "not_found_ttl" values we can test against.
    my $config = $ldap->ldap_config;
    $config->{ttl} = 86400;
    $config->{not_found_ttl} = 3600;
    $ldap->add_to_ldap_config;

    return $ldap;
}

###############################################################################
# Grab the "cached_at" time for a User, straight from the DB.
#
# Don't want to do it by checking against a User or Homunculus, as we
# over-ride "cached_at" for certain scenarios (e.g. ST:U:Deleted).
sub get_user_cached_at {
    my $key = shift;
    my $val = shift;
    my ($driver) = grep { /LDAP/ } Socialtext::User->_drivers();
    my $cached_at = sql_singlevalue( qq{
        SELECT cached_at
          FROM users
         WHERE driver_key = ?
           AND $key = ?
    }, $driver, $val );
    return sql_parse_timestamptz($cached_at);
}

###############################################################################
# TEST: Users found in LDAP are _not_ considered to be "missing".
existing_user_not_missing: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => 'John Doe');
    isa_ok $user, 'Socialtext::User', 'existing User';
    ok !$user->missing, '... who is marked as _not_ missing';

    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: User deemed "missing" when not in LDAP.
missing_when_not_in_ldap: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => 'John Doe');
    isa_ok $user, 'Socialtext::User', 'existing User';

    # Grab the User directly from LDAP (so we can re-add him again later)
    my $conn = Socialtext::LDAP->new();
    my $dn   = $user->driver_unique_id;
    my $mesg = $conn->{ldap}->search(
        base   => $dn,
        filter => '(objectClass=inetOrgPerson)',
        attrs  => ['*'],
    );
    my ($entry) = $mesg->entries;
    ok $entry, '... found User entry in LDAP';

    # remove User from LDAP; should be "missing"
    remove_user: {
        my $mesg = $conn->{ldap}->delete($dn);
        ok !$mesg->is_error, '... removed User from LDAP';

        my $cached_at_before = get_user_cached_at(driver_unique_id => $dn);
        clear_log();

        $user->homunculus->expire;
        $user = Socialtext::User->new(username => 'John Doe');
        ok $user, '... ... requeried the User';
        ok $user->missing, '... ... and has been flagged as "missing"';
        logged_like 'info', qr/$dn.*missing/, '... ... logged to nlw.log';

        my $cached_at_after = get_user_cached_at(driver_unique_id => $dn);
        ok $cached_at_after > $cached_at_before,
            '... ... "cached_at" was updated';
    }

    # add User back into LDAP; should be "found" again
    restore_user: {
        my $mesg = $conn->{ldap}->add($entry);
        ok !$mesg->is_error, '... added User back into LDAP';

        my $cached_at_before = get_user_cached_at(driver_unique_id => $dn);
        clear_log();

        $user->homunculus->expire;
        $user = Socialtext::User->new(username => 'John Doe');
        ok $user, '... ... requeried the User';
        ok !$user->missing, '... ... and has been flagged as "found"';
        logged_like 'info', qr/$dn.*found/, '... ... logged to nlw.log';

        my $cached_at_after = get_user_cached_at(driver_unique_id => $dn);
        ok $cached_at_after > $cached_at_before,
            '... ... "cached_at" was updated';
    }

    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: Missing Users are always a "ST::User::Deleted".  Deleted Users have
# *special* behaviour, so we want to make sure that if a User goes missing
# that we always treat them the same.  Not just "$user->is_deleted", but the
# full suite of over-rides found in ST::User::Deleted;
missing_users_are_deleted_users: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => 'John Doe');
    my $conn = Socialtext::LDAP->new();
    my $dn   = $user->driver_unique_id;

    my $mesg = $conn->{ldap}->delete($dn);
    ok !$mesg->is_error, 'removed User from LDAP';

    # Expire/refresh; should be missing/deleted
    $user->homunculus->expire;
    $user = Socialtext::User->new(username => 'John Doe');
    ok $user->missing, '... marked as "missing"';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted',
        '... with a ST::U::Deleted homunculus';

    # Refresh from cache; should *still* be missing/deleted
    $user = Socialtext::User->new(username => 'John Doe');
    ok $user->missing, '... still missing';
    isa_ok $user->homunculus, 'Socialtext::User::Deleted',
        '... still with ST::U::Deleted homunculus';

    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
# TEST: Re-use cached data up to "not_found_ttl" for missing Users
reuse_cached_data_while_missing: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => 'John Doe');
    my $conn = Socialtext::LDAP->new();
    my $dn   = $user->driver_unique_id;

    # Remove User from LDAP, expire, and refresh (so he's marked as missing)
    my $mesg = $conn->{ldap}->delete($dn);
    ok !$mesg->is_error, 'removed User from LDAP';

    $user->homunculus->expire;
    $user = Socialtext::User->new(username => 'John Doe');

    # Re-query the User, and make sure we grab the cached copy (and do *NOT*
    # go out to LDAP).
    requery_using_cache: {
        Socialtext::LDAP->ResetStats();

        # multiple lookups, so we know we didn't at all go to LDAP
        for (1 .. 3) {
            Socialtext::LDAP->ConnectionCache->clear();
            $user = Socialtext::User->new(username => 'John Doe');
        }
        ok $user, 'refreshed User';
        is $Socialtext::LDAP::stats{connect}, 0, '... using cache, not LDAP';
        ok $user->missing, '... still missing';
    }

    # Move us past the "not_found_ttl" and re-query again.  This time we
    # *should* go out to LDAP to check if the User is there.
    requery_from_ldap: {
        # Twiddle User so it looks like its stale w.r.t. "not_found_ttl", but
        # still valid/fresh w.r.t. "ttl" (so if we refresh, we know it was the
        # "not_found_ttl" that was used).
        my $not_found_ttl = $ldap->ldap_config->{not_found_ttl};
        my $user_id       = $user->user_id;
        sql_execute( qq{
            UPDATE users
               SET cached_at = cached_at - ?::interval
             WHERE user_id = ?

        }, $not_found_ttl + 60, $user_id );

        # multiple lookups, so we know we went to LDAP once (and only once)
        Socialtext::LDAP->ResetStats();
        for (1 .. 3) {
            Socialtext::LDAP->ConnectionCache->clear();
            $user = Socialtext::User->new(username => 'John Doe');
        }
        ok $user, 'refreshed User';
        is $Socialtext::LDAP::stats{connect}, 1, '... from LDAP';
        ok $user->missing, '... still missing';
        ok $user->is_deleted, '... and is_deleted';
    }

    Test::Socialtext::User->delete_recklessly($user);
}
