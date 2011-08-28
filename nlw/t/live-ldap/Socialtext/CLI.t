#!perl
# @COPYRIGHT@

use strict;
use warnings;
use File::Slurp qw(write_file);
use Test::Socialtext::Bootstrap::OpenLDAP;
use Test::Socialtext;
use Socialtext::CLI;
use Socialtext::Account;
use Test::Socialtext::CLIUtils qw(expect_failure expect_success call_cli_argv);
use Test::Socialtext::User;

BEGIN {
    require Socialtext::People::Profile;
    plan skip_all => 'People is not linked in' if ($@);
    plan tests => 90;
}

fixtures( 'db', 'destructive' );

###############################################################################
sub bootstrap_openldap {
    my $openldap = Test::Socialtext::Bootstrap::OpenLDAP->new();
    isa_ok $openldap, 'Test::Socialtext::Bootstrap::OpenLDAP';
    ok $openldap->add_ldif('t/test-data/ldap/base_dn.ldif'),
        '.. added data: base_dn';
    ok $openldap->add_ldif('t/test-data/ldap/people.ldif'),
        '... added data: people';
    ok $openldap->add_ldif('t/test-data/ldap/groups-groupOfNames.ldif'),
        '... added data: groups';
    return $openldap;
}

###############################################################################
MASS_ADD_USERS: {
    my $ldap = bootstrap_openldap();

    # force automatic creation of People Profile fields, so we don't have to
    # set them all up ourselves here prior to running the test.
    local $Socialtext::People::Fields::AutomaticStockFields=1;

    # mass-add an LDAP user
    # - is required for the 'update_ldap_user' test that comes below
    add_ldap_user: {
        # create CSV file, matching a user in the LDAP store
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone}) . "\n",
            join(',', 'John Doe', qw(ignored@example.com ignored_first ignored_last ignored_password position company location work_phone mobile_phone home_phone));

        # do mass-add
        expect_success(
            call_cli_argv(mass_add_users =>
                '--csv' => $csvfile,
            ),
            qr/\QUpdated user John Doe\E/,
            'mass-add-users successfully added LDAP user'
        );

        # verify that the User record contains the data from LDAP, and not the
        # data that we provided in the CSV
        my $user = Socialtext::User->new(username => 'John Doe');
        ok $user, 'found test user';
        isa_ok $user->homunculus, 'Socialtext::User::LDAP', '... which is an LDAP user';
        is $user->username, 'john doe', '... using username from LDAP';
        is $user->first_name, 'John', '... using first_name from LDAP';
        is $user->last_name, 'Doe', '... using last_name from LDAP';
        is $user->password, '*no-password*', '... using password from LDAP';

        # verify that a People profile was created with the data from CSV
      SKIP: {
          skip 'Socialtext People is not installed', 7 unless $Socialtext::MassAdd::Has_People_Installed;
            my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse => 1);
            ok $profile, '... ST People profile was found';
            is $profile->get_attr('position'), 'position', '... ... using position from CSV';
            is $profile->get_attr('company'), 'company', '... ... using company from CSV';
            is $profile->get_attr('location'), 'location', '... ... using location from CSV';
            is $profile->get_attr('work_phone'), 'work_phone', '... ... using work_phone from CSV';
            is $profile->get_attr('mobile_phone'), 'mobile_phone', '... ... using mobile_phone from CSV';
            is $profile->get_attr('home_phone'), 'home_phone', '... ... using home_phone from CSV';
        }
    }

    # mass-update an LDAP user
    # - relies on the 'add_ldap_user' test above having been run to create the
    #   user
    update_ldap_user: {
        # create CSV file, to try to update the LDAP user created in the
        # 'add_ldap_user' test above
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            join(',', qw{username email_address first_name last_name password position company}) . "\n",
            join(',', 'John Doe', qw(updated@example.com updated_first updated_last updated_password updated_position updated_company));

        # do mass-add
        expect_success(
            call_cli_argv(mass_add_users =>
                '--csv' => $csvfile,
            ),
            qr/\QUpdated user John Doe\E/,
            'mass-add-users successfully updated LDAP user'
        );

        # verify that the User record still contains the data from LDAP, and
        # not the data that we provided in the CSV
        my $user = Socialtext::User->new(username => 'John Doe');
        ok $user, 'found test user';
        isa_ok $user->homunculus, 'Socialtext::User::LDAP', '... which is an LDAP user';
        is $user->username, 'john doe', '... using username from LDAP';
        is $user->first_name, 'John', '... using first_name from LDAP';
        is $user->last_name, 'Doe', '... using last_name from LDAP';
        is $user->password, '*no-password*', '... using password from LDAP';

        # verify that our People profile updates were applied
      SKIP: {
          skip 'Socialtext People is not installed', 7 unless $Socialtext::MassAdd::Has_People_Installed;
            my $profile = Socialtext::People::Profile->GetProfile($user, no_recurse => 1);
            ok $profile, '... ST People profile was found';
            is $profile->get_attr('position'), 'updated_position', '... ... using position from CSV';
            is $profile->get_attr('company'), 'updated_company', '... ... using company from CSV';
            is $profile->get_attr('location'), 'location', '... ... using original location';
            is $profile->get_attr('work_phone'), 'work_phone', '... ... using original work_phone';
            is $profile->get_attr('mobile_phone'), 'mobile_phone', '... ... using original mobile_phone';
            is $profile->get_attr('home_phone'), 'home_phone', '... ... using original home_phone';
        }
    }
}

###############################################################################
update_ldap_user_fails: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => "John Doe");

    isa_ok $user, 'Socialtext::User', 'got a user';

    expect_failure(
        call_cli_argv(set_user_names =>
            '--username'   => 'John Doe',
            '--first-name' => 'Sean',
        ),
        qr/\QRemotely sourced Users cannot be updated via Socialtext.\E/,
        '... who cannot have values updated'
    );
}

###############################################################################
change_pwd_ldap_user_fails: {
    my $ldap = bootstrap_openldap();
    my $user = Socialtext::User->new(username => "John Doe");

    isa_ok $user, 'Socialtext::User', 'got a user';

    expect_failure(
        call_cli_argv(change_password =>
            '--username' => 'John Doe',
            '--password' => 'pwd',
        ),
        qr/\QRemotely sourced passwords cannot be updated via Socialtext.\E/,
        '... who cannot have values updated'
    );

    Test::Socialtext::User->delete_recklessly($user);
}

###############################################################################
create_group: {
    my $ldap          = bootstrap_openldap();
    my $def_acct      = Socialtext::Account->Default;
    my $def_acct_name = $def_acct->name();
    my $motorhead_dn  = 'cn=Motorhead,dc=example,dc=com';

    # Group lookups should be done *in-process*
    no warnings 'once';
    local $Socialtext::Group::Factory::Asynchronous = 0;

    create_group_default_account: {
        expect_success(
            call_cli_argv(create_group =>
                '--ldap-dn' => $motorhead_dn,
            ),
            qr/\QThe Motorhead Group has been created in the $def_acct_name Account.\E/,
            'create-group loads LDAP Group',
        );

        # Verify that Group was created with correct Account
        my $proto = Socialtext::Group->GetProtoGroup(
            driver_unique_id => $motorhead_dn,
        );
        ok $proto, '... was vivified into DB';
        is $proto->{primary_account_id}, $def_acct->account_id,
            '... into default Primary Account';

        # CLEANUP
        my $group = Socialtext::Group->GetGroup($proto);
        Test::Socialtext::Group->delete_recklessly( $group );
    }

    create_group_already_exists: {
        my $group = Socialtext::Group->GetGroup(
            driver_unique_id => $motorhead_dn,
        );
        expect_failure(
            call_cli_argv(create_group =>
                '--ldap-dn' => $motorhead_dn,
            ),
            qr/\QThe Motorhead Group has already been added to the system.\E/,
            'create-group fails to create duplicate LDAP Group',
        );

        # CLEANUP
        Test::Socialtext::Group->delete_recklessly( $group );
    }

    create_group_explicit_account: {
        my $test_acct      = Socialtext::Account->Socialtext();
        my $test_acct_name = $test_acct->name();

        expect_success(
            call_cli_argv(create_group =>
                '--ldap-dn' => $motorhead_dn,
                '--account' => $test_acct_name,
            ),
            qr/\QThe Motorhead Group has been created in the $test_acct_name Account.\E/,
            'create-group loads LDAP Group',
        );

        # Verify that Group was created with correct Account
        my $proto = Socialtext::Group->GetProtoGroup(
            driver_unique_id => $motorhead_dn,
        );
        ok $proto, '... was vivified into DB';
        is $proto->{primary_account_id}, $test_acct->account_id,
            '... into explicit Primary Account';

        # CLEANUP
        my $group = Socialtext::Group->GetGroup($proto);
        Test::Socialtext::Group->delete_recklessly( $group );
    }

    create_group_nonexistent_dn: {
        my $bad_dn = 'cn=Non-existent,dc=example,dc=com';
        expect_failure(
            call_cli_argv(create_group =>
                '--ldap-dn' => $bad_dn,
            ),
            qr/Cannot find Group with DN '$bad_dn'\./,
            'create group with non-existent LDAP DN',
        );
    }
}

###############################################################################
create_group_no_ldap: {
    my $motorhead_dn  = 'cn=Motorhead,dc=example,dc=com';
    expect_failure(
        call_cli_argv(create_group =>
            '--ldap-dn' => $motorhead_dn,
        ),
        qr/\QNo LDAP Group Factories configured; cannot create Group from LDAP.\E/,
        'create-group shows error if no LDAP Group Factories configured',
    );
}

###############################################################################
add_member_to_ldap_group: {
    my $ldap  = bootstrap_openldap();
    my $user  = create_test_user();
    my $group = Socialtext::Group->GetGroup(
        driver_unique_id => 'cn=Motorhead,dc=example,dc=com',
    );

    isa_ok $group, 'Socialtext::Group', 'Have an LDAP Group';
    expect_failure(
        call_cli_argv(add_member =>
            '--group' => $group->group_id,
            '--email' => $user->email_address,
        ),
        qr/\QRemotely sourced Groups cannot be updated via Socialtext\E/,
        'Cannot add_member to an LDAP group'
    );

    # Clean up after ourselves
    Test::Socialtext::Group->delete_recklessly( $group );
}

###############################################################################
remove_user_from_ldap_group: {
    my $ldap  = bootstrap_openldap();
    my $user  = create_test_user();
    my $group = Socialtext::Group->GetGroup(
        driver_unique_id => 'cn=Motorhead,dc=example,dc=com',
    );

    isa_ok $group, 'Socialtext::Group', 'Have an LDAP Group';
    expect_failure(
        call_cli_argv(remove_member =>
            '--group' => $group->group_id,
            '--email' => $user->email_address,
        ),
        qr/\QRemotely sourced Groups cannot be updated via Socialtext\E/,
        'Cannot remove_member from an LDAP group'
    );

    # Clean up after ourselves
    Test::Socialtext::Group->delete_recklessly( $group );
}

###############################################################################
ldap_sourced_profile_fields_cannot_be_set: {
    local $Socialtext::People::Fields::AutomaticStockFields    = 1;
    local $Socialtext::Pluggable::Plugin::People::Asynchronous = 0;


    # Test data
    my $field      = 'work_phone';
    my $username   = 'John Doe';
    my $real_value = '+1 234 555-1212';
    my $new_value  = '+1 416 123-4567';

    # Create an Account to test in, and enable People Plugin for that Account
    my $account = create_test_account_bypassing_factory();
    $account->enable_plugin('people');

    # Bootstrap LDAP, and map a People Profile field to be LDAP sourced
    my $ldap = bootstrap_openldap();
    {
        my $people  = Socialtext::Pluggable::Adapter->plugin_class('people');
        $people->SetProfileField( {
            name    => $field,
            source  => 'external',
            account => $account,
        } );

        my $ldap_config = $ldap->ldap_config();
        $ldap_config->{attr_map}{work_phone} = 'telephoneNumber';
        Socialtext::LDAP::Config->save($ldap_config);
    }

    # Load up an LDAP User, and put them in a People enabled Account
    my $user = Socialtext::User->new(username => $username);
    isa_ok $user->homunculus, 'Socialtext::User::LDAP', 'Got LDAP sourced User';
    $user->primary_account($account);

    # Refresh the User, so we know that we've pulled their Profile Data from
    # LDAP.
    $user->homunculus->expire();
    $user = Socialtext::User->new(username => $username);
    {
        my $profile = Socialtext::People::Profile->GetProfile($user->user_id);
        ok $profile, '... and found their People Profile';

        my $phone = $profile->get_attr($field);
        is $phone, '+1 234 555-1212', '... ... with value pulled from LDAP';
    }

    # TEST: should *not* be able to set LDAP sourced profile field via CLI
    cannot_set_profile_field: {
        expect_failure(
            call_cli_argv(set_user_profile =>
                '--username' => $username,
                $field, $new_value,
            ),
            qr/Profile Field '$field' is externally sourced/,
            '... and which cannot be updated as its externally sourced',
        );

        # refresh Profile, make sure the value did *NOT* get set
        my $profile = Socialtext::People::Profile->GetProfile($user->user_id);
        is $profile->get_attr($field), $real_value,
            '... ... and which did not get updated';
    }
}
