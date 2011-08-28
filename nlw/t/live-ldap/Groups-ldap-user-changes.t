#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Socialtext::Group;
use Socialtext::User;
use Socialtext::LDAP;
use Socialtext::Group::Factory;
use Socialtext::LDAP::Config;
use Socialtext::User::LDAP::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 56;

# Force this to be synchronous.
local $Socialtext::Group::Factory::Asynchronous = 0;

###############################################################################
# Fixtures:     db
#
# Need the DB set up, but don't really care what's in it.
fixtures(qw( db ));

###############################################################################
# TEST DATA:
our $dn = 'cn=Test User,ou=people,dc=example,dc=com';
our $changed_dn = 'cn=Test User,ou=terminated,dc=example,dc=com';

our $email = 'TestUser@null.socialtext.com';
our $changed_email = 'changed@null.socialtext.com';

our $username = 'Test Username';
our $changed_username = 'changed username';

our %user_attrs = (
    cn             => 'Test User',
    givenName      => 'Test',
    sn             => 'User',
    mail           => $email,
    employeeNumber => $username,
    objectClass    => 'inetOrgPerson',
    userPassword   => 'abc123',
    ou             => 'people',
);

our $group_dn = 'cn=Test Group,dc=example,dc=com';
our %group_attrs = (
    cn          => 'Test Group',
    objectClass => 'groupOfNames',
    member      => [$dn],
);

###############################################################################
# List of ST fields that are stored internally as *lower-case*.
our %is_lower_cased_internally = (
    email_address   => 1,
    username        => 1,
);

###############################################################################
# Helper; bootstrap OpenLDAP and set up our DCs and OUs
sub bootstrap_openldap {
    # bootstrap OpenLDAP
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();

    # use "employeeNumber" as the username, so we can change it without having
    # to change the "dn" for the user at the same time.
    my $config   = $openldap->ldap_config();
    $config->{attr_map}{username} = 'employeeNumber';
    Socialtext::LDAP::Config->save($config);

    # add baseline data to OpenLDAP
    $openldap->add_ldif( 't/test-data/ldap/base_dn.ldif' );
    $openldap->add_ldif( 't/test-data/ldap/people.ldif' );

    # return the OpenLDAP object back to the caller; when it goes out of scope
    # it'll be shut down.
    return $openldap;
}

###############################################################################
# Helper: runs a single test
sub test_ldap_data_changes {
    my %opts = @_;
    my $title            = $opts{title};
    my $update_cb        = $opts{do_update};
    my $expected_changes = $opts{expected_changes};

    # Turn *OFF* the LDAP User and Group caches, so that we're forcing
    # ourselves to go back to the LDAP directory to look stuff up each time.
    local $Socialtext::User::LDAP::Factory::CacheEnabled = 0;
    local $Socialtext::Group::Factory::CacheEnabled = 0;

    # Bootstrap OpenLDAP, add our test user and group, and vivify them in ST.
    my $guard    = Test::Socialtext::User->snapshot();
    my $openldap = bootstrap_openldap();

    ok 1, "======================================================================";
    ok 1, "TEST: $title";

    my $conn = Socialtext::LDAP->new();
    my $ldap = $conn->{ldap};

    my $mesg = $ldap->add($dn, attrs => [%user_attrs]);
    ok !$mesg->is_error, 'added test user to LDAP';
    $mesg->is_error && diag $mesg->error;

    $mesg = $ldap->add($group_dn, attrs => [%group_attrs]);
    ok !$mesg->is_error, 'added test group to LDAP';
    $mesg->is_error && diag $mesg->error;
    my $group = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    my $user  = $group->users->next();
    my $user_count = Socialtext::User->Count();

    # Expire the Group and User (so they'll be forcably refreshed)
    $group->expire();
    $user->homunculus->expire();

    # Updated LDAP, then re-vivify the Group (and User) in ST
    $update_cb->( $ldap );
    my $changed_group
        = Socialtext::Group->GetGroup(driver_unique_id => $group_dn);
    my $changed_user = $changed_group->users->next();
    my $changed_user_count = Socialtext::User->Count();

    # CHECK: are we looking at the same group?
    is $changed_group->group_id, $group->group_id,
        'refreshed Group has matching group_id; its same group';
    isnt $changed_group->cached_at->hires_epoch,
        $group->cached_at->hires_epoch,
        '... and *has* been refreshed';

    # CHECK: are we looking at the same user?
    is $changed_user->user_id, $user->user_id,
        'refreshed User has matching user_id; its same guy';
    isnt $changed_user->cached_at->hires_epoch,
        $user->cached_at->hires_epoch,
        '... and *has* been refreshed';

    # CHECK: we didn't accidentally vivify a *new* User behind the scenes
    is $changed_user_count, $user_count,
        'did *not* accidentally add a new User record';

    # CLEANUP
    Test::Socialtext::Group->delete_recklessly($changed_group);
}

###############################################################################
# Helper: maps an LDAP attribute to the ST field it represents
sub user_attr_to_field {
    my ($conn, $attr) = @_;
    my $attr_map = $conn->config->{attr_map};
    foreach my $field (keys %{$attr_map}) {
        return $field if ($attr eq $attr_map->{$field});
    }
    return;
}

###############################################################################
# TEST: change the e-mail address.
test_ldap_email_address_change: {
    # Helper method to change the User record
    my $cb_change_email_address = sub {
        my $ldap = shift;
        my $mesg = $ldap->modify($dn, replace => [mail => $changed_email]);
        ok !$mesg->is_error, "updated User's e-mail address in LDAP";
        $mesg->is_error && diag $mesg->error;
    };

    # Go run our test
    test_ldap_data_changes(
        title            => "Change e-mail address",
        do_update        => $cb_change_email_address,
        expected_changes => {
            mail => $changed_email,
        },
    );
}

###############################################################################
# TEST: change the username
test_ldap_username_change: {
    # Helper method to change the User record
    my $cb_change_username = sub {
        my $ldap = shift;
        my $mesg = $ldap->modify($dn, replace => [employeeNumber => $changed_username]);
        ok !$mesg->is_error, "updated User's username in LDAP";
        $mesg->is_error && diag $mesg->error;
    };

    # Go run our test
    test_ldap_data_changes(
        title            => "Change username",
        do_update        => $cb_change_username,
        expected_changes => {
            employeeNumber => $changed_username,
        },
    );
}

###############################################################################
# TEST: change the DN, and move the user around the LDAP tree
test_ldap_dn_change: {
    # Helper method to change the User record
    my $cb_change_dn = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($changed_dn, attr => [%user_attrs]);
        ok !$mesg->is_error, 'moved User to new DN in LDAP';
        $mesg->is_error && diag $mesg->error;

        # update the Group to point to the User's new DN
        $mesg = $ldap->modify($group_dn,
            replace => [member => [$changed_dn]],
        );
        ok !$mesg->is_error, 'updated Group to point to new User DN';
        $mesg->is_error && diag $mesg->error;
    };

    # Go run our test
    test_ldap_data_changes(
        title            => "Change DN",
        do_update        => $cb_change_dn,
        expected_changes => {
            dn => $changed_dn,
        },
    );
}

###############################################################################
# TEST: change the DN, and e-mail address
test_ldap_dn_and_email: {
    my %updated_user_attrs = (
        %user_attrs,
        mail            => $changed_email,
    );

    # Helper method to change the User record
    my $cb_change_user = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($changed_dn, attr => [%updated_user_attrs]);
        ok !$mesg->is_error, 'moved user to new DN in LDAP, w/new e-mail';
        $mesg->is_error && diag $mesg->error;

        # update the Group to point to the User's new DN
        $mesg = $ldap->modify($group_dn,
            replace => [member => [$changed_dn]],
        );
        ok !$mesg->is_error, 'updated Group to point to new User DN';
        $mesg->is_error && diag $mesg->error;
    };

    # Go run our test
    test_ldap_data_changes(
        title            => "Changing DN and e-mail",
        do_update        => $cb_change_user,
        expected_changes => {
            dn   => $changed_dn,
            mail => $changed_email,
        },
    );
}

###############################################################################
# TEST: change the DN, and username
test_ldap_dn_and_username: {
    my %updated_user_attrs = (
        %user_attrs,
        employeeNumber  => $changed_username,
    );

    # Helper method to change the User record
    my $cb_change_user = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($changed_dn, attr => [%updated_user_attrs]);
        ok !$mesg->is_error, 'moved user to new DN in LDAP, w/new username';
        $mesg->is_error && diag $mesg->error;

        # update the Group to point to the User's new DN
        $mesg = $ldap->modify($group_dn,
            replace => [member => [$changed_dn]],
        );
        ok !$mesg->is_error, 'updated Group to point to new User DN';
        $mesg->is_error && diag $mesg->error;
    };

    # Go run our test
    test_ldap_data_changes(
        title            => "Changing DN and username",
        do_update        => $cb_change_user,
        expected_changes => {
            dn             => $changed_dn,
            employeeNumber => $changed_username,
        },
    );
}
