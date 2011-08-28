#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 61;
use Test::Socialtext::User;
use Socialtext::Account;
use File::Slurp qw(write_file);
use Email::Send::Test;

BEGIN { use_ok 'Socialtext::CLI' }
use Test::Socialtext::CLIUtils qw(:all);

fixtures( 'db' );

$Socialtext::EmailSender::Base::SendClass = 'Test';

MASS_ADD_USERS: {
    my $guard   = Test::Socialtext::User->snapshot;
    my $default = Socialtext::Account->Default();

    add_users_from_csv: {
        # create CSV file
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone preferred_name}) . "\n",
            join(',', qw{csvtest1 csvtest1@example.com John Doe passw0rd position company location work_phone mobile_phone home_phone JohnDoe}) . "\n",
            join(',', qw{csvtest2 csvtest2@example.com Jane Smith password2 position2 company2 location2 work_phone2 mobile_phone2 home_phone2 JaneSmith}) . "\n";

        # do mass-add
        expect_success(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile]
                )->mass_add_users();
            },
            qr/\QAdded user csvtest1\E.*\QAdded user csvtest2\E/s,
            'mass-add-users successfully added users',
        );
        unlink $csvfile;

        # verify first user was added, including all fields
        my $user = Socialtext::User->new( username => 'csvtest1' );
        ok $user, 'csvtest1 user was created via mass_add_users';
        is $user->email_address, 'csvtest1@example.com', '... email_address was set';
        is $user->first_name, 'John', '... first_name was set';
        is $user->last_name, 'Doe', '... last_name was set';
        ok $user->password_is_correct('passw0rd'), '... password was set';
        is $user->primary_account->account_id, $default->account_id,
            'user has default primary_account';

        SKIP: {
            skip('Socialtext People is not installed', 7)
                unless $Socialtext::MassAdd::Has_People_Installed;

            my $profile = Socialtext::People::Profile->GetProfile(
                $user, no_recurse => 1);
            ok $profile, '... ST People profile was created';
            is $profile->get_attr('position'), 'position',
                '... ... position was set';
            is $profile->get_attr('company'), 'company',
                '... ... company was set';
            is $profile->get_attr('location'), 'location',
                '... ... location was set';
            is $profile->get_attr('work_phone'), 'work_phone',
                '... ... work_phone was set';
            is $profile->get_attr('mobile_phone'), 'mobile_phone',
                '... ... mobile_phone was set';
            is $profile->get_attr('home_phone'), 'home_phone',
                '... ... home_phone was set';
            is $profile->get_attr('preferred_name'), 'JohnDoe',
                '... ... preferred_name was set';
        }

        # verify second user was added, but presume fields were added ok
        $user = Socialtext::User->new( username => 'csvtest2' );
        ok $user, 'csvtest2 user was created via mass_add_users';
    }

    add_users_from_csv_with_account: {
        my $acct = create_test_account_bypassing_factory();

        # create CSV file
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone}) . "\n",
            join(',', qw{csvtest3 csvtest3@example.com John Doe passw0rd position company location work_phone mobile_phone home_phone}) . "\n";

        # do mass-add
        expect_success(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile, '--account', $acct->name]
                )->mass_add_users();
            },
            qr/\QAdded user csvtest3\E/,
            'mass-add-users successfully added users',
        );
        unlink $csvfile;

        # verify first user was added, including all fields
        my $user = Socialtext::User->new( username => 'csvtest3' );
        ok $user, 'csvtest1 user was created via mass_add_users';
        is $user->primary_account->account_id, $acct->account_id,
            'user has specific primary_account';
    }

    update_users_from_csv: {
        my $acct = create_test_account_bypassing_factory();
        $acct->enable_plugin('people');

        # create CSV file, using user from above test
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file( $csvfile,
            "username,email_address,first_name,last_name,password,position\n"
               ."csvtest1,email\@example.com,u_John,u_Doe,u_passw0rd,u_position"
        );

        # make sure that the user really does exist
        my $user = Socialtext::User->new( username => 'csvtest1' );
        ok $user, 'csvtest1 user exists prior to update';

        # do mass-update
        expect_success(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile, '--account', $acct->name ],
                )->mass_add_users();
            },
            qr/\QUpdated user csvtest1\E/,
            'mass-add-users successfully updated users',
        );
        unlink $csvfile;

        # verify user was updated, including the People fields
        $user = Socialtext::User->new( username => 'csvtest1' );
        ok $user, 'csvtest1 user still around after update';
        is $user->email_address, 'csvtest1@example.com',
            '... email was *NOT* updated (by design)';
        is $user->first_name, 'u_John',
            '... first_name was updated';
        is $user->last_name, 'u_Doe',
            '... last_name was updated';
        ok $user->password_is_correct('u_passw0rd'),
            '... password was updated';
        is $acct->role_for_user($user)->name, 'member',
            'mass updated user added to account';

        SKIP: {
            skip('Socialtext People is not installed', 2)
                unless $Socialtext::MassAdd::Has_People_Installed;

            my $profile = Socialtext::People::Profile->GetProfile(
                $user, no_recurse => 1);
            ok $profile, '... ST People profile was found';
            is $profile->get_attr('position'), 'u_position',
                '... ... position was updated';
        }
    }

    # failure; email in use by another user
    email_in_use_by_another_user: {
        my $user = create_test_user();
        my $username = $user->username;

        # create CSV file, using e-mail from a known existing user
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]);
        write_file( $csvfile,
            "username,email_address,first_name,last_name,password\n"
                . "csv_email_clash,$username,John,Doe,passw0rd"
        );

        # do mass-add
        expect_failure(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile],
                )->mass_add_users();
            },
            qr/The email address you provided \([^\)]+\) is already in use./,
            'mass-add-users does not add user if email in use'
        );
        unlink $csvfile;
    }

    # failure; no CSV file provided
    no_csv_file_provided: {
        expect_failure(
            sub { 
                Socialtext::CLI->new( argv=>[] )->mass_add_users();
            },
            qr/\QThe file you provided could not be read\E/,
            'mass-add-users failed with no args'
        );
    }

    # failure; file is not CSV
    file_is_not_csv: {
        # create bogus file
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            join(',', qw{username email_address first_name last_name password}) . "\n",
            join(' ', qw{csvtest1 csvtest1@example.com John Doe passw0rd}) . "\n";

        # do mass-add
        expect_failure(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile]
                )->mass_add_users();
            },
            qr/\Qcould not be parsed (missing fields).  Skipping this user.\E/,
            'mass-add-users failed with invalid file'
        );
        unlink $csvfile;
    }

    private_external_id: {
        my $name1 = Test::Socialtext::create_unique_id() . '@example.com';
        my $name2 = Test::Socialtext::create_unique_id() . '@example.com';
        my $id = 'abc123';
        my $csvfile = Cwd::abs_path(
            (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
        );
        write_file $csvfile,
            "username,email_address,private_external_id\n"
            ."$name1,$name1,$id\n";

        expect_success(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile],
                )->mass_add_users();
            },
            qr/Added user \Q$name1\E/,
            'mass-add-users with external ID passes',
        );

        # mass-add with a colliding external ID
        write_file $csvfile,
            "username,email_address,private_external_id\n"
            ."$name2,$name2,$id\n";
        expect_failure(
            sub {
                Socialtext::CLI->new(
                    argv => ['--csv', $csvfile],
                )->mass_add_users();
            },
            qr/The private external id you provided \([^\)]+\) is already in use./,
            'mass-add-users with colliding external ID fails',
        );
    }
}

add_users_with_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;

    # create CSV file
    my $csvfile = Cwd::abs_path(
        (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
    );
    write_file $csvfile,
        join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone preferred_name}) . "\n",
        join(',', qw{csvtest1 csvtest1@example.com John Doe passw0rd position company location work_phone mobile_phone home_phone JohnDoe}) . "\n",
        join(',', qw{csvtest2 csvtest2@example.com Jane Smith password2 position2 company2 location2 work_phone2 mobile_phone2 home_phone2 JaneSmith}) . "\n";

    # mass add Users with restrictions
    Email::Send::Test->clear;
    expect_success(
        call_cli_argv(
            'mass-add-users',
            '--csv'         => $csvfile,
            '--restriction' => 'password_change',
        ),
        qr/Added user.*Added user/s,
        'mass-add-users successfully added users',
    );

    my $user_one = Socialtext::User->new(username => 'csvtest1');
    ok $user_one, '... found first user';
    ok $user_one->password_change_confirmation, '... ... password change set';
    ok !$user_one->email_confirmation, '... ... NO e-mail confirmation set';

    my $user_two = Socialtext::User->new(username => 'csvtest2');
    ok $user_two, '... found first user';
    ok $user_two->password_change_confirmation, '... ... password change set';
    ok !$user_two->email_confirmation, '... ... NO e-mail confirmation set';

    my @emails = Email::Send::Test->emails();
    is @emails, 2, '... and e-mails were sent to each User';
}

add_users_multiple_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;

    # create CSV file
    my $csvfile = Cwd::abs_path(
        (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
    );
    write_file $csvfile,
        join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone preferred_name}) . "\n",
        join(',', qw{csvtest1 csvtest1@example.com John Doe passw0rd position company location work_phone mobile_phone home_phone JohnDoe}) . "\n";

    # mass add Users with restrictions
    Email::Send::Test->clear;
    expect_success(
        call_cli_argv(
            'mass-add-users',
            '--csv'         => $csvfile,
            '--restriction' => 'password_change',
            '--restriction' => 'email_confirmation',
        ),
        qr/Added user/s,
        'mass-add-users successfully added users',
    );

    my $user = Socialtext::User->new(username => 'csvtest1');
    ok $user, '... found test User';
    ok $user->password_change_confirmation, '... ... password change set';
    ok $user->email_confirmation, '... ... e-mail confirmation set';

    my @emails = Email::Send::Test->emails();
    is @emails, 2, '... and e-mails were sent (one for each restriction)';
}

add_invalid_restriction: {
    my $guard = Test::Socialtext::User->snapshot;

    # create CSV file
    my $csvfile = Cwd::abs_path(
        (File::Temp::tempfile(SUFFIX=>'.csv', OPEN=>0))[1]
    );
    write_file $csvfile,
        join(',', qw{username email_address first_name last_name password position company location work_phone mobile_phone home_phone preferred_name}) . "\n",
        join(',', qw{csvtest1 csvtest1@example.com John Doe passw0rd position company location work_phone mobile_phone home_phone JohnDoe}) . "\n";

    # mass add Users with restrictions
    Email::Send::Test->clear;
    expect_failure(
        call_cli_argv(
            'mass-add-users',
            '--csv'         => $csvfile,
            '--restriction' => 'invalid-restriction',
        ),
        qr/unknown restriction type, 'invalid-restriction'/,
        '... failed due to unknown restriction type'
    );

    my $user = Socialtext::User->new(username => 'csvtest1');
    ok !$user, '... and User was *not* added';
}
