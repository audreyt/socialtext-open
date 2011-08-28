#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use Test::More;
use Test::Socialtext;
use Test::Socialtext::Fatal;
use Test::Socialtext::User;
use Guard qw(scope_guard);
use Socialtext::Account;
use Socialtext::MassAdd;
use Socialtext::People::Profile;

# Force the use of a Test e-mail sender, otherwise we send real e-mails out
BEGIN {
    unless ( eval { require Email::Send::Test; 1 } ) {
        plan skip_all => 'These tests require Email::Send::Test to run.';
    }
    else {
        plan tests => 140;
    }
    $Socialtext::EmailSender::Base::SendClass = 'Test';
}

fixtures(qw( db ));

my %userinfo = (
    username      => 'ronnie',
    email_address => 'ronnie@mrshow.example.com',
    first_name    => 'Ronnie',
    last_name     => 'Dobbs',
    password      => 'brut4liz3',
    position      => 'Criminal',
    company       => 'FUZZ',
    location      => '',
    work_phone    => '',
    mobile_phone  => '',
    home_phone    => ''
);

my $DefaultAccount   = Socialtext::Account->Default;
my $DefaultAccountId = $DefaultAccount->account_id;
$DefaultAccount->enable_plugin('people');

Add_from_hash: {
    my $guard = Test::Socialtext::User->snapshot;

    add_new_user: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->add_user(%userinfo);
        is_deeply \@successes, ['Added user ronnie'], 'success message ok';
        logged_like 'info', qr/Added user ronnie/, '... message also logged';
        is_deeply \@failures, [], 'no failure messages';

        my $user = Socialtext::User->new(username => 'ronnie');
        ok !$user->requires_email_confirmation, 'email confirmation is not required';
        is $user->primary_account_id, $DefaultAccountId,
            'User added to Default account';

        my @emails = Email::Send::Test->emails;
        ok !@emails, 'confirmation email not sent';
    }

    add_existing_user_to_account: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };

        my $user = Socialtext::User->new(username => 'ronnie');

        my (@successes, @failures);
        my $acct = create_test_account_bypassing_factory();
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
            account => $acct,
        );
        $mass_add->add_user(%userinfo);
        is_deeply \@successes, ['Updated user ronnie'], 'success message ok';
        logged_like 'info', qr/Updated user ronnie/, '... message also logged';
        is_deeply \@failures, [], 'no failure messages';

        is $user->primary_account_id, $DefaultAccountId,
            "did not update ronnie's primary_account";
        my $role = $acct->role_for_user($user);
        is $role->name, 'member', 'user got added to the account';
    }

    bad_profile_field: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };

        local $userinfo{badfield} = 'badvalue';

        my @successes;
        my @failures;
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->add_user(%userinfo);
        is_deeply \@successes, ['No changes for user ronnie'], 'success message ok';
        logged_like 'info', qr/No changes for user ronnie/, '... message also logged';
        is scalar(@failures), 1, "just one failure";
        like $failures[0], qr/Profile field "badfield" could not be updated/;
        logged_like 'error',
            qr/Profile field "badfield" could not be updated/,
            '... message also logged';
    }
}

add_user_to_account_again: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # add the User to the system
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { },
        fail_cb => sub { },
    );
    ok !exception { $mass_add->add_user(%userinfo) }, 'Added User';

    # create a new test Account and make this User a member
    my $account = create_test_account_bypassing_factory;
    my $user    = Socialtext::User->new(username => 'ronnie');
    $account->add_user(user => $user);

    # add this User again, *explicitly* to this Account
    my $success = '';
    $mass_add = Socialtext::MassAdd->new(
        account => $account,
        pass_cb => sub { $success = $_[0] },
        fail_cb => sub { },
    );

    ok !exception {
        $mass_add->add_user(%userinfo);
    }, 're-added user is added without incident';
}

my $PIRATE_CSV = <<'EOT';
username,email_address,first_name,middle_name,last_name,password,position,company,location,work_phone,mobile_phone,home_phone
guybrush,guybrush@example.com,Guybrush,Ulysses,Threepwood,my_password,Captain,Pirates R. Us,High Seas,123-456-YARR,,123-HIGH-SEA
EOT

Add_one_user_csv: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($PIRATE_CSV);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    logged_like 'info', qr/Added user guybrush/, '... message also logged';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'guybrush');
    ok !$user->requires_email_confirmation, 'email confirmation is not required';

    my @emails = Email::Send::Test->emails;
    ok !@emails, 'confirmation email not sent';
}

Add_user_already_added: {
    my $guard = Test::Socialtext::User->snapshot;

    # add the User to the system
    my (@g_successes, @g_failures);
    my $g_mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @g_successes, shift },
        fail_cb => sub { push @g_failures,  shift },
    );
    $g_mass_add->from_csv($PIRATE_CSV);
    my $user    = Socialtext::User->new(username => 'guybrush');
    my $user_id = $user->user_id;

    uneditable_profile_field: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };
        local $userinfo{mobile_phone} = '1-877-AVAST-YE';

        # make the "mobile_phone" field externally sourced
        my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
        $people->SetProfileField( {
            name    => 'mobile_phone',
            source  => 'external',
            account => $DefaultAccount,
        } );
        scope_guard {
            $people->SetProfileField( {
                name    => 'mobile_phone',
                source  => 'user',
                account => $DefaultAccount,
            } );
        };

        # add/update User, but be sure that we log failure on externally
        # sourced fields
        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->add_user(%userinfo);
        is scalar(@failures), 1, "just one failure";
        like $failures[0], qr/Profile field "mobile_phone" could not be updated/;
        logged_like 'error',
            qr/Profile field "mobile_phone" could not be updated/,
            '... message also logged';

        is_deeply \@successes, ['Added user ronnie'], 'success message ok';
        logged_like 'info', qr/Added user ronnie/, '... message also logged';
    }

    Profile_data_needs_update: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        $user->profile->set_attr('mobile_phone', '1-888-555-1212');
        $user->profile->save();

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['Updated user guybrush'], 'success message ok';
        logged_like 'info', qr/Updated user guybrush/, '... message also logged';
        is_deeply \@failures, [], 'no failure messages';
    }

    Profile_data_already_up_to_date: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['No changes for user guybrush'],
            'success message ok';
        is_deeply \@failures, [], 'no failure messages';
    }

    Password_gets_updated: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        $user->update_store(password => 'elaine');
        ok $user->password_is_correct('elaine'), 'password faked for test';

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['Updated user guybrush'], 'success message ok';
        is_deeply \@failures, [], 'no failure messages';

        $user->reload;
        ok $user->password_is_correct('my_password'), 'password was updated';
    }

    Password_untouched: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        $user->update_store(
            first_name => 'to-be-overwritten',
            password   => 'joanna',
        );
        ok $user->password_is_correct('joanna'), 'password faked for test';

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );

        my $NO_PASSWORD_CSV = <<'EOT';
Username,Email Address,First Name
guybrush,guybrush@example.com,Guybrush
EOT
        $mass_add->from_csv($NO_PASSWORD_CSV);
        is_deeply \@successes, ['Updated user guybrush'], 'success message ok';
        is_deeply \@failures, [], 'no failure messages';

        $user->reload;
        is $user->first_name, 'Guybrush', 'first_name was updated';
        ok $user->password_is_correct('joanna'), 'password was untouched';

        my @emails = Email::Send::Test->emails;
        ok !@emails, 'NO confirmation email sent';
    }

    First_last_name_update: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        $user->update_store(
            first_name  => 'Herman',
            middle_name => 'Sasafras',
            last_name   => 'Toothrot',
        );
# XXX $user->reload;
        is $user->first_name,  'Herman',   'first names over-ridden';
        is $user->middle_name, 'Sasafras', 'middle name over-ridden';
        is $user->last_name,   'Toothrot', 'last name over-ridden';

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['Updated user guybrush'], 'success message ok';
        is_deeply \@failures, [], 'no failure messages';

        $user->reload;
        is $user->first_name,  'Guybrush',   'first_name was updated';
        is $user->middle_name, 'Ulysses',    'middle_name was updated';
        is $user->last_name,   'Threepwood', 'last_name was updated';
    }

    Profile_update: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        $user->profile->set_attr(position   => 'Chef');
        $user->profile->set_attr(company    => 'Scumm Bar');
        $user->profile->set_attr(location   => 'Monkey Island');
        $user->profile->set_attr(work_phone => '123-456-YUCK');
        $user->profile->save;
        is $user->profile->get_attr('position'), 'Chef', 'Profile over-ridden';

        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['Updated user guybrush'], 'success message ok';
        is_deeply \@failures, [], 'no failure messages';

        $user->reload;
        my $profile = $user->profile;
        is $profile->get_attr('position'),   'Captain',       'People position was updated';
        is $profile->get_attr('company'),    'Pirates R. Us', 'People company was updated';
        is $profile->get_attr('location'),   'High Seas',     'People location was updated';
        is $profile->get_attr('work_phone'), '123-456-YARR',  'People work_phone was updated';
    }

    Update_with_no_people_installed: {
        scope_guard { Email::Send::Test->clear() };
        scope_guard { clear_log(); };
        scope_guard { $user->reload };

        local $Socialtext::MassAdd::Has_People_Installed = 0;
        my (@successes, @failures);
        my $mass_add = Socialtext::MassAdd->new(
            pass_cb => sub { push @successes, shift },
            fail_cb => sub { push @failures,  shift },
        );
        $mass_add->from_csv($PIRATE_CSV);
        is_deeply \@successes, ['No changes for user guybrush'],
            'success message ok';
        is_deeply \@failures, [], 'no failure messages';
    }
}

Quoted_csv: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $quoted_csv = <<"EOT";
username,email_address,first_name,last_name,password,position,company,location,work_phone,mobile_phone,home_phone
"lechuck","ghost\@lechuck.example.com","Ghost Pirate","LeChuck","my_password","Ghost","Ghost Pirates Inc","Netherworld","","",""
guybrush,guybrush\@example.com,Guybrush,Threepwood,my_password,Captain,Pirates R. Us,High Seas,123-456-YARR,,123-HIGH-SEA
EOT
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($quoted_csv);
    is_deeply \@successes, ['Added user lechuck', 'Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';
}

Csv_field_order_unimportant: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $ODD_ORDER_CSV = <<'EOT';
last_name,first_name,username,email_address
Threepwood,Guybrush,guybrush,guybrush@example.com
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($ODD_ORDER_CSV);

    # make sure we were able to add the user
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';
}

csv_with_dos_windows_crlf: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    (my $DOS_FORMAT_CSV = $PIRATE_CSV) =~ s/\n/\r\n/g;

    # make sure that the CSV has DOS/Windows CR/LF at EOL
    like $DOS_FORMAT_CSV, qr/\r\n/, 'DOS/Windows formatted CSV';

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($DOS_FORMAT_CSV);

    # make sure we were able to add the user
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';
}

csv_with_mac_crlf: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    (my $MAC_FORMAT_CSV = $PIRATE_CSV) =~ s/\n/\r/g;

    # make sure that the CSV has Mac LF at EOL
    like $MAC_FORMAT_CSV, qr/\r/, 'Mac formatted CSV';

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($MAC_FORMAT_CSV);

    # make sure we were able to add the user
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';
}

Contains_utf8: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $utf8_csv = <<'EOT';
username,email_address,first_name,last_name,password,position,company,location,work_phone,mobile_phone,home_phone
yamadat,yamadat@example.com,太郎,山田,パスワード太,社長,日本電気株式会社,location,+81 3 3333 4444,+81 70 1234 5678,
EOT
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($utf8_csv);
    is_deeply \@successes, ['Added user yamadat'], 'success message ok, with utf8';
    is_deeply \@failures, [], 'no failure messages, with utf8';
}

Bad_email_address: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $bad_csv = $PIRATE_CSV . <<'EOT';
lechuck,example.com,Ghost,Pirate,LeChuck,my_password,Ghost,Ghost Pirates Inc,Netherworld,,,
EOT

    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($bad_csv);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures,
        ['Line 3: "example.com" is not a valid email address.'],
        'correct failure message';
    logged_like 'error',
        qr/\QLine 3: "example.com" is not a valid email address/,
        '... message also logged';
}

Duplicate_email_address: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $user = create_test_user(
        email_address => 'duplicate@example.com',
    );

    # use a duplicate e-mail address (one already in use)
    (my $csv = $PIRATE_CSV) =~ s/guybrush@/duplicate@/;
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($csv);
    is_deeply \@successes, [], 'user was not added';
    is_deeply \@failures, ['Line 2: The email address you provided (duplicate@example.com) is already in use.'], 'correct failure message';
}

No_password_causes_email_to_be_sent: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # strip out the password from the csv line
    (my $csv = $PIRATE_CSV) =~ s/my_password//;
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($csv);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'guybrush');
    ok $user->requires_email_confirmation, 'email confirmation is required';

    my @emails = Email::Send::Test->emails;
    is @emails, 1, 'confirmation email sent';
}

Bad_password: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # Change the password to something too small
    (my $csv = $PIRATE_CSV) =~ s/my_password/pw/;
    clear_log();
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($csv);
    is_deeply \@successes, [], 'user was not added';
    is_deeply \@failures,
        ['Line 2: Passwords must be at least 6 characters long.'],
        'correct failure message';
    logged_like 'error', qr/Passwords must be at least 6 characters long/, '... message also logged';
}

Create_user_with_no_people_installed: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    local $Socialtext::MassAdd::Has_People_Installed = 0;

    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($PIRATE_CSV);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'guybrush');
    ok !$user->requires_email_confirmation, 'email confirmation is not required';

    my @emails = Email::Send::Test->emails;
    ok !@emails, 'confirmation email not sent';
}

Missing_username: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $bad_csv = $PIRATE_CSV . <<'EOT';
,ghost@lechuck.example.com,Ghost,Pirate,LeChuck,password,Ghost,Ghost Pirates Inc,Netherworld,,,
EOT
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($bad_csv);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures,
        ['Line 3: username is a required field, but it is not present.'],
        'correct failure message';
}

Missing_email: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $bad_csv = $PIRATE_CSV . <<'EOT';
lechuck,,Ghost,Pirate,LeChuck,password,Ghost,Ghost Pirates Inc,Netherworld,,,
EOT
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($bad_csv);
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures,
        ['Line 3: email is a required field, but it is not present.'],
        'correct failure message';
}

Bogus_csv: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $bad_csv = <<"EOT";
username,email_address,first_name,last_name,password,position,company,location,work_phone,mobile_phone,home_phone
This line isn't CSV but we're going to try to parse/process it anyways
lechuck\tghost\@lechuck.example.com\tGhost Pirate\tLeChuck\tpassword\tGhost\tGhost Pirates Inc\tNetherworld\t\t\t
guybrush,guybrush\@example.com,Guybrush,Threepwood,password,Captain,Pirates R. Us,High Seas,123-456-YARR,,123-HIGH-SEA
EOT
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($bad_csv);
    is_deeply \@failures,
        ['Line 2: could not be parsed (missing fields).  Skipping this user.',
         'Line 3: could not be parsed (missing fields).  Skipping this user.',
        ],
        'correct failure message';
    is_deeply \@successes, ['Added user guybrush'], 'continued on to add next user';
}

Fields_for_account: {
    no warnings 'redefine', 'once';
    local *Socialtext::People::Fields::new = sub { "dummy" };
    my $acct = Socialtext::Account->Default;
    my $fields = Socialtext::MassAdd->ProfileFieldsForAccount($acct);
    is $fields, "dummy";
}

my $FLEET_CSV = <<'EOT';
username,email_address,first_name,last_name,password,position,company,location,work_phone,mobile_phone,home_phone
guybrush,guybrush@example.com,Guybrush,Threepwood,password,Captain,Pirates R. Us,High Seas,123-456-YARR,mobile1,123-HIGH-SEA
bluebeard,bluebeard@example.com,Blue,Beard,password,Captain,Pirates R. Us,High Seas,123-456-YARR,mobile2,123-HIGH-SEA
EOT

Add_multiple_users_failure: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # make the "mobile_phone" field externally sourced
    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    $people->SetProfileField( {
        name    => 'mobile_phone',
        source  => 'external',
        account => $DefaultAccount,
    } );
    scope_guard {
        $people->SetProfileField( {
            name    => 'mobile_phone',
            source  => 'user',
            account => $DefaultAccount,
        } );
    };

    # add the Users
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->from_csv($FLEET_CSV);
    is_deeply \@successes, ['Added user guybrush','Added user bluebeard'], 'success message ok';
    logged_like 'info', qr/Added user guybrush/, '... message also logged';
    logged_like 'info', qr/Added user bluebeard/, '... message also logged';
    is scalar(@failures), 1, 'only one error message per field updating failure';
    like $failures[0],
        qr/Profile field "mobile_phone" could not be updated/,
        '... correct failure message';
}

Missing_username_in_csv_header: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $BOGUS_CSV = <<'EOT';
email_address,first_name,last_name,password
guybrush@example.com,Guybrush,Threepwood,guybrush_password
ghost@lechuck.example.com,Ghost Pirate,LeChuck,lechuck_password
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($BOGUS_CSV);

    # make sure we failed, and *why*
    is scalar @successes, 0,
        'failed to add User(s) when missing username in CSV header';
    is_deeply \@failures,
        [
        'Line 1: could not be parsed.  The file was missing the following required fields (username).  The file must have a header row listing the field headers.'
        ], '... correct failure message';
    is scalar(@failures), 1, '... and ONLY ONE error message recorded';
}

Missing_email_in_csv_header: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $BOGUS_CSV = <<'EOT';
username,first_name,last_name
guybrush,Guybrush,Threepwood
lechuck,Ghost Pirate,LeChuck
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($BOGUS_CSV);

    # make sure we failed, and *why*
    is scalar @successes, 0,
        'failed to add User(s) when missing email address in CSV header';
    is_deeply \@failures,
        [
        'Line 1: could not be parsed.  The file was missing the following required fields (email_address).  The file must have a header row listing the field headers.'
        ], '... correct failure message';
    is scalar(@failures), 1, '... and ONLY ONE error message recorded';
}

Missing_csv_header: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $BOGUS_CSV = <<'EOT';
guybrush,guybrush@example.com,Guybrush,Threepwood,guybrush_password
lechuck,ghost@lechuck.example.com,Ghost Pirate,LeChuck,lechuck_password
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($BOGUS_CSV);

    # make sure we failed, and *why*
    is scalar @successes, 0, 'failed to add User(s) when missing CSV header';
    is_deeply \@failures,
        [
        'Line 1: could not be parsed.  The file was missing the following required fields (username, email_address).  The file must have a header row listing the field headers.'
        ], '... correct failure message';
    is scalar(@failures), 1, '... and ONLY ONE error message recorded';
}

Csv_header_has_more_columns_than_data: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $BOGUS_CSV = <<'EOT';
username,email_address,first_name,last_name,password
guybrush,guybrush@example.com,Guybrush,Threepwood
lechuck,ghost@lechuck.example.com,Ghost Pirate,LeChuck
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($BOGUS_CSV);

    # make sure we failed, and *why*
    is scalar @successes, 0,
        'failed to add User(s) with missing data columns';
    is_deeply \@failures,
        [
        'Line 2: could not be parsed (missing fields).  Skipping this user.',
        'Line 3: could not be parsed (missing fields).  Skipping this user.'
        ],
        '... correct failure messages';
    is scalar(@failures), 2, '... one error message per User failure';
}

Csv_header_has_less_columns_than_data: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    my $BOGUS_CSV = <<'EOT';
username,email_address,first_name,last_name
guybrush,guybrush@example.com,Guybrush,Threepwood,guybrush_password
lechuck,ghost@lechuck.example.com,Ghost Pirate,LeChuck,lechuck_password
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # try to add the user
    $mass_add->from_csv($BOGUS_CSV);

    # make sure we failed, and *why*
    is scalar @successes, 0,
        'failed to add User(s) with *extra* data columns';
    is_deeply \@failures,
        [
        'Line 2: could not be parsed (extra fields).  Skipping this user.',
        'Line 3: could not be parsed (extra fields).  Skipping this user.'
        ],
        '... correct failure messages';
    is scalar(@failures), 2, '... one error message per User failure';
}

Csv_header_cleanup: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # CSV with:
    #   a)  CamelCase headers,
    #   b)  Leading/trailing whitespace (which should be ignored)
    #   c)  Embedded whitespace (which should be turned into "_"s)
    my $CAMEL_CSV = <<'EOT';
Username , Email Address , First Name , Last Name , Password, Position , Company , Location
guybrush,guybrush@example.com,Guybrush,Threepwood,my_password,Captain,Pirates R. Us,High Seas
EOT

    # set up the MassAdd-er
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );

    # add the user
    $mass_add->from_csv($CAMEL_CSV);

    # make sure the User got added ok, and that the Profile was updated
    # properly
    is_deeply \@successes, ['Added user guybrush'], 'success message ok';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'guybrush');
    my $profile = $user->profile;
    is $profile->get_attr('position'), 'Captain',       'People position was updated';
    is $profile->get_attr('company'),  'Pirates R. Us', 'People company was updated';
    is $profile->get_attr('location'), 'High Seas',     'People location was updated';
}

Adding_a_deactivated_user: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # Add the User
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->add_user(%userinfo);

    # De-activate the User
    my $user = Socialtext::User->new(username => 'ronnie');
    ok $user->deactivate, 'User de-activated';
    ok $user->is_deactivated, '... and has been deactivated';

    # mass-add the Users
    @successes = @failures = ();
    my $acct = Socialtext::Account->create(name => "test-$$-2");
    $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
        account => $acct,
    );
    $mass_add->add_user(%userinfo);
    is_deeply \@successes, ['Updated user ronnie'], 'success message ok';
    logged_like 'info', qr/Updated user ronnie/, '... message also logged';
    is_deeply \@failures, [], 'no failure messages';

    my $role = $acct->role_for_user($user);
    ok $role;
    is $role->name, 'member', 'user got added to the account';

    $user->reload;
    ok !$user->is_deactivated, "ronnie got re-activated";
}

Add_user_with_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # Add a User, with some restrictions
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb      => sub { push @successes, shift },
        fail_cb      => sub { push @failures,  shift },
        restrictions => [qw( email_confirmation password_change require_external_id )],
    );
    $mass_add->add_user(%userinfo);

    is_deeply \@successes, ['Added user ronnie'], 'success message ok';
    logged_like 'info', qr/Added user ronnie/, '... message also logged';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'ronnie');
    ok $user, 'User created with restrictions';

    my @restrictions = map { $_->restriction_type } $user->restrictions->all;
    my @expected     = qw( email_confirmation password_change require_external_id );
    is_deeply \@restrictions, \@expected, '... expected restrictions';

    my @emails = Email::Send::Test->emails;
    is @emails, 2, '... and two e-mails were sent (one for each restriction)';
}

Update_user_with_restrictions: {
    my $guard = Test::Socialtext::User->snapshot;
    scope_guard { Email::Send::Test->clear() };
    scope_guard { clear_log(); };

    # Add the User, so we've got something to update
    my (@successes, @failures);
    my $mass_add = Socialtext::MassAdd->new(
        pass_cb => sub { push @successes, shift },
        fail_cb => sub { push @failures,  shift },
    );
    $mass_add->add_user(%userinfo);

    @successes = @failures = ();
    clear_log;

    # Go update the User, assigning them a restriction
    $mass_add = Socialtext::MassAdd->new(
        pass_cb      => sub { push @successes, shift },
        fail_cb      => sub { push @failures,  shift },
        restrictions => [qw( email_confirmation )],
    );
    $mass_add->add_user(%userinfo);

    is_deeply \@successes, ['Updated user ronnie'], 'success message ok';
    logged_like 'info', qr/Updated user ronnie/, '... message also logged';
    is_deeply \@failures, [], 'no failure messages';

    my $user = Socialtext::User->new(username => 'ronnie');
    ok $user->email_confirmation, '... e-mail confirmation is set';
    ok !$user->password_change_confirmation, '... no password change set';

    my @emails = Email::Send::Test->emails;
    is @emails, 1, '... e-mail was sent for applied restriction';
}
