#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::JobCreator';
use Socialtext::AppConfig;
use Socialtext::Hub;
use Socialtext::User;
use Socialtext::LDAP;
use Socialtext::LDAP::Config;
use Socialtext::User::LDAP::Factory;
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext tests => 517;

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
our $changed_given = 'Frank';

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

    for my $user (Socialtext::User->All->all()) {
        next if $user->is_system_created;
        Test::Socialtext::User->delete_recklessly($user);
    }

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
    my $lookup_before_cb = $opts{lookup_before};
    my $lookup_after_cb  = $opts{lookup_after};
    my $update_cb        = $opts{do_update};
    my $expected_changes = $opts{expected_changes};

    # Turn *OFF* the LDAP User cache, so that we're forcing ourselves to go
    # back to the LDAP directory to look stuff up each time.
    local $Socialtext::User::LDAP::Factory::CacheEnabled = 0;

    # Bootstrap OpenLDAP, add our test user, and instantiate them in ST.
    my $openldap = bootstrap_openldap();

    ok 1, "======================================================================";
    ok 1, "TEST: $title";

    my $conn = Socialtext::LDAP->new();
    my $ldap = $conn->{ldap};
    my $mesg = $ldap->add($dn, attrs => [%user_attrs]);
    ok !$mesg->is_error, 'added test user to LDAP';
    $mesg->is_error && diag $mesg->error;

    my $user = $lookup_before_cb->();

    # Change the user in LDAP, and re-instantiate them in ST.
    $update_cb->( $ldap );
    my $changed_user = $lookup_after_cb->();

    # CHECK: are we looking at the same user?
    is $changed_user->user_id, $user->user_id, '... has matching user_id; its same guy';

    # CHECK: data should be as we expect it; only the field(s) that got
    # changed were updated.
    #
    # Gets a little ugly as we have to map "ldap attributes" to "ST fields".
    my $changed_homey = $changed_user->homunculus;
    my %expected_results = (
        %user_attrs,                # the original user
        dn => $dn,                  # and his DN
        %{$expected_changes},       # plus the expected changes
    );
    foreach my $ldap_attr (sort keys %expected_results) {
        # Find the ST field that maps to this LDAP attribute, skipping the
        # attribute if its not part of the attr_map
        my $st_field = attr_to_field($conn, $ldap_attr);
        next unless $st_field;

        # in a homunculus, the LDAP "user_id" is the "driver_unique_id"
        $st_field = 'driver_unique_id' if ($st_field eq 'user_id');

        # Get the value that we're expecting.
        #
        # *Some* fields, its stored internally as lower-case.
        my $value = $expected_results{$ldap_attr};
        if ($is_lower_cased_internally{$st_field}) {
            $value = lc($value);
        }

        # ok... do they match?
        is $changed_homey->$st_field, $value,
            "... $st_field is as expected; $value";
    }
}

###############################################################################
# Helper: maps an LDAP attribute to the ST field it represents
sub attr_to_field {
    my ($conn, $attr) = @_;
    my $attr_map = $conn->config->{attr_map};
    foreach my $field (keys %{$attr_map}) {
        return $field if ($attr eq $attr_map->{$field});
    }
    return;
}

###############################################################################
# Helper: do a user lookup, and tell us how it was done.
sub user_lookup {
    my ($field, $value) = @_;
    my $user = Socialtext::User->new($field => $value);
    isa_ok $user, 'Socialtext::User';
    ok 1, "... user look-up done as '$field' => '$value'";
    return $user;
}

###############################################################################
# TEST: change the e-mail address.
test_ldap_email_address_change: {
    my $user;   # queried user record will go here

    # Helper method to change the User record
    my $cb_change_email_address = sub {
        my $ldap = shift;
        my $mesg = $ldap->modify($dn, replace => [mail => $changed_email]);
        ok !$mesg->is_error, 'updated e-mail address in LDAP';
        $mesg->is_error && diag $mesg->error;
    };

    # Lookups that we'll do *after* the User data has been changed.
    my @test_cases = (
        [ 'email address (new)' => sub { user_lookup(email_address => $changed_email) } ],
        [ 'username'            => sub { user_lookup(username => $username)           } ],
        [ 'driver_unique_id'    => sub { user_lookup(driver_unique_id => $dn)         } ],
        [ 'user_id'             => sub { user_lookup(user_id => $user->user_id)       } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Change e-mail, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_email_address,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                mail => $changed_email,
            },
        );
    }
}

###############################################################################
# TEST: change the givenName
test_ldap_givenName_change: {
    my $user;   # queried user record will go here

    # Helper method to change the User record
    my $cb_change_given_name = sub {
        my $ldap = shift;

        @Socialtext::JobCreator::to_index = ();
        
        my $mesg = $ldap->modify($dn, replace => [givenName => $changed_given]);
        ok !$mesg->is_error, 'updated e-mail address in LDAP';
        $mesg->is_error && diag $mesg->error;

        Socialtext::User->Resolve($username);
        is scalar(@Socialtext::JobCreator::to_index), 1, 'an index job created';
    };

    # Go run all of our tests
    test_ldap_data_changes(
        title               => "Change given name",
        lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
        do_update           => $cb_change_given_name,
        lookup_after        => sub { $user = user_lookup(driver_unique_id => $dn) },
        expected_changes    => {
            givenName => $changed_given,
        },
    );
}

###############################################################################
# TEST: change the username
test_ldap_username_change: {
    my $user;   # queried user record will go here

    # Helper method to change the User record
    my $cb_change_username = sub {
        my $ldap = shift;
        my $mesg = $ldap->modify($dn, replace => [employeeNumber => $changed_username]);
        ok !$mesg->is_error, 'updated username in LDAP';
        $mesg->is_error && diag $mesg->error;
    };

    # Lookups that we'll do *after* the User data has been changed.
    my @test_cases = (
        [ 'email address'       => sub { user_lookup(email_address => $email)       } ],
        [ 'username (new)'      => sub { user_lookup(username => $changed_username) } ],
        [ 'driver_unique_id'    => sub { user_lookup(driver_unique_id => $dn)       } ],
        [ 'user_id'             => sub { user_lookup(user_id => $user->user_id)     } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Change username, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_username,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                employeeNumber  => $changed_username,
            },
        );
    }
}

###############################################################################
# TEST: change the DN, and move the user around the LDAP tree
test_ldap_dn_change: {
    my $user;   # queried user record will go here

    # Helper method to change the User record
    my $cb_change_dn = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($changed_dn, attr => [%user_attrs]);
        ok !$mesg->is_error, 'moved user to new DN in LDAP';
        $mesg->is_error && diag $mesg->error;
    };

    # Lookups that we'll do *after* the User data has changed
    my @test_cases = (
        [ 'email address'           => sub { user_lookup(email_address => $email)           } ],
        [ 'username'                => sub { user_lookup(username => $username)             } ],
        [ 'driver_unique_id (new)'  => sub { user_lookup(driver_unique_id => $changed_dn)   } ],
        [ 'user_id'                 => sub { user_lookup(user_id => $user->user_id)         } ],
    );

    # XXX:
    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Change dn, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_dn,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                dn  => $changed_dn,
            },
        );
    }
}

###############################################################################
# TEST: convert everything from CamelCase to lower-case
test_ldap_camelcase_to_lowercase_change: {
    my $user;   # queried user record will go here

    # Lower-cased version of the User data
    my $lower_dn        = lc($dn);
    my $lower_cn        = lc($user_attrs{cn});
    my $lower_email     = lc($email);
    my $lower_username  = lc($username);

    my %lower_user_attrs = (
        %user_attrs,
        cn              => $lower_cn,
        mail            => $lower_email,
        employeeNumber  => $lower_username,
    );

    # Helper method to change the User record
    my $cb_change_camel_to_lower = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($lower_dn, attr => [%lower_user_attrs]);
        ok !$mesg->is_error, 'moved user to new DN in LDAP, all lower-case';
        $mesg->is_error && diag $mesg->error;
    };

    # Lookups that we'll do *after* the User data has changed
    my @test_cases = (
        [ 'email address (old)'     => sub { user_lookup(email_address => $email)       } ],
        [ 'email address (new)'     => sub { user_lookup(email_address => $lower_email) } ],
        [ 'username (old)'          => sub { user_lookup(username => $username)         } ],
        [ 'username (new)'          => sub { user_lookup(username => $lower_username)   } ],
        [ 'driver_unique_id (old)'  => sub { user_lookup(driver_unique_id => $dn)       } ],
        [ 'driver_unique_id (new)'  => sub { user_lookup(driver_unique_id => $lower_dn) } ],
        [ 'user_id'                 => sub { user_lookup(user_id => $user->user_id)     } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Changing CamelCase to lower-case, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_camel_to_lower,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                dn              => $lower_dn,
                cn              => $lower_cn,
                mail            => $lower_email,
                employeeNumber  => $lower_username,
            },
        );
    }
}

###############################################################################
# TEST: convert everything from lower-case to CamelCase
test_ldap_lowercase_to_camelcase_change: {
    my $user;   # queried user record will go here

    # Hang onto a copy of the CamelCase user info
    my $camel_dn         = $dn;
    my $camel_cn         = $user_attrs{cn};
    my $camel_email      = $email;
    my $camel_username   = $username;
    my %camel_user_attrs = %user_attrs;

    # Lower-cased version of the User data
    my $lower_dn         = lc($dn);
    my $lower_cn         = lc($user_attrs{cn});
    my $lower_email      = lc($email);
    my $lower_username   = lc($username);
    my %lower_user_attrs = (
        %user_attrs,
        cn              => $lower_cn,
        mail            => $lower_email,
        employeeNumber  => $lower_username,
    );

    # Make the "lower case" user the one we start the test with
    local %user_attrs = %lower_user_attrs;
    local $dn         = $lower_dn;

    # Helper method to change the User record
    my $cb_change_lower_to_camel = sub {
        my $ldap = shift;

        # delete the User record at the old DN
        my $mesg = $ldap->delete($lower_dn);
        ok !$mesg->is_error, 'removed user in LDAP';
        $mesg->is_error && diag $mesg->error;

        # create a new User record at the new DN
        $mesg = $ldap->add($camel_dn, attr => [%camel_user_attrs]);
        ok !$mesg->is_error, 'moved user to new DN in LDAP, all CamelCase';
        $mesg->is_error && diag $mesg->error;
    };

    # Lookups that we'll do *after* the User data has changed
    my @test_cases = (
        [ 'email address (old)'     => sub { user_lookup(email_address => $lower_email) } ],
        [ 'email address (new)'     => sub { user_lookup(email_address => $camel_email) } ],
        [ 'username (old)'          => sub { user_lookup(username => $lower_username)   } ],
        [ 'username (new)'          => sub { user_lookup(username => $camel_username)   } ],
        [ 'driver_unique_id (old)'  => sub { user_lookup(driver_unique_id => $lower_dn) } ],
        [ 'driver_unique_id (new)'  => sub { user_lookup(driver_unique_id => $camel_dn) } ],
        [ 'user_id'                 => sub { user_lookup(user_id => $user->user_id)     } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Changing lower-case to CamelCase, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $lower_dn) },
            do_update           => $cb_change_lower_to_camel,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                dn              => $camel_dn,
                cn              => $camel_cn,
                mail            => $camel_email,
                employeeNumber  => $camel_username,
            },
        );
    }
}

###############################################################################
# TEST: change the DN, and e-mail address
test_ldap_dn_and_email: {
    my $user;   # queried user record will go here

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
    };

    # Lookups to do *after* the User data has changed
    my @test_cases = (
        [ 'email address (new)'     => sub { user_lookup(email_address => $changed_email) } ],
        [ 'username'                => sub { user_lookup(username => $username)           } ],
        [ 'driver_unique_id (new)'  => sub { user_lookup(driver_unique_id => $changed_dn) } ],
        [ 'user_id'                 => sub { user_lookup(user_id => $user->user_id)       } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Changing DN and e-mail, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_user,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                dn      => $changed_dn,
                mail    => $changed_email,
            },
        );
    }
}

###############################################################################
# TEST: change the DN, and username
test_ldap_dn_and_username: {
    my $user;   # queried user record will go here

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
    };

    # Lookups to do *after* the User data has changed
    my @test_cases = (
        [ 'email address'           => sub { user_lookup(email_address => $email)         } ],
        [ 'username (new)'          => sub { user_lookup(username => $changed_username)   } ],
        [ 'driver_unique_id (new)'  => sub { user_lookup(driver_unique_id => $changed_dn) } ],
        [ 'user_id'                 => sub { user_lookup(user_id => $user->user_id)       } ],
    );

    # Go run all of our tests
    foreach my $test (@test_cases) {
        my ($title, $cb_lookup_after) = @{$test};
        test_ldap_data_changes(
            title               => "Changing DN and username, lookup by $title",
            lookup_before       => sub { $user = user_lookup(driver_unique_id => $dn) },
            do_update           => $cb_change_user,
            lookup_after        => $cb_lookup_after,
            expected_changes    => {
                dn              => $changed_dn,
                employeeNumber  => $changed_username,
            },
        );
    }
}
