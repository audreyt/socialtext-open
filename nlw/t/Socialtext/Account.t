#!perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 121;
use Test::Socialtext::User;
use Test::Socialtext::Fatal;
use Test::Differences;
use Socialtext::File;
use MIME::Base64 ();
use YAML qw/LoadFile/;

use Socialtext::Pluggable::Plugin::TestPlugin;

BEGIN {
    use_ok( 'Socialtext::Account' );
    use_ok( 'Socialtext::Workspace' );
}
fixtures(qw( clean db ));

is( Socialtext::Account->Count(), 4, 'three accounts in DBMS at start' );
my $test = Socialtext::Account->create( name => 'Test Account' );
isa_ok( $test, 'Socialtext::Account', 'create returns a new Socialtext::Account object' );
users_are($test, []);
is( Socialtext::Account->Count(), 5, 'Now we have four accounts' );

my $unknown = Socialtext::Account->Unknown;
isa_ok( $unknown, 'Socialtext::Account' );
ok( $unknown->is_system_created, 'Unknown account is system-created' );
users_are($unknown, []);

my $deleted = Socialtext::Account->Deleted;
isa_ok( $deleted, 'Socialtext::Account' );
ok( $deleted->is_system_created, 'Deleted account is system-created' );
users_are($deleted, []);

my $socialtext = Socialtext::Account->Socialtext;
isa_ok( $socialtext, 'Socialtext::Account' );
ok( $socialtext->is_system_created, 'Unknown account is system-created' );
users_are($socialtext, []);
eq_or_diff [ sort @{$socialtext->user_ids} ], [], 'user_ids() works';

like exception { Socialtext::Account->create(name => 'Test Account') },
    qr/already in use/, 'cannot create two accounts with the same name';

like exception { $unknown->update(name => 'new name') },
    qr/cannot change/, 'cannot change the name of a system-created account';

my $ws = Socialtext::Workspace->create(
    name       => 'testingspace',
    title      => 'testing',
    account_id => $test->account_id,
);
isa_ok( $ws, 'Socialtext::Workspace' );

# Create some test data for the test account
# 3 users, 2 in a workspace (1 hidden, 1 visible), 1 outside the workspace.
{
    for my $n ( 1..3 ) {
        my $user = Socialtext::User->create(
            username      => "dummy$n",
            email_address => "devnull$n\@example.com",
            password      => 'password',
            primary_account_id => 
               ($n != 1 ? $test->account_id : $socialtext->account_id),
        );
        isa_ok( $user, 'Socialtext::User' );

        $ws->add_user( user => $user ) unless $n == 3;
    }
}

Rudimentary_Plugin_Test: {
   $socialtext->enable_plugin( 'dashboard' );
   is('1', $socialtext->is_plugin_enabled('dashboard'), 'dashboard enabled.');
   my %enabled = map { $_ => 1 } $socialtext->plugins_enabled;
   eq_or_diff( \%enabled, { widgets => 1, dashboard => 1 }, 'enabled.');
   $socialtext->disable_plugin( 'dashboard' );
   is('0', $socialtext->is_plugin_enabled('dashboard'), 'dashboard disabled.');
}

is( $test->workspace_count, 1, 'test account has one workspace' );
is( $test->workspaces->next->name, 'testingspace',
    'testingspace workspace belong to testing account' );
users_are($test, [qw/dummy1 dummy2 dummy3/], 0);
users_are($test, [qw/dummy2 dummy3/], 1);

Rename_account: {
    my $new_name = 'Ronwell Quincy Dobbs';
    my $account = Socialtext::Account->create(name => 'ronnie dobbs');
    $account->update(name => $new_name);
    is $account->name, $new_name, 'account name was changed';
    $account = Socialtext::Account->new(name => $new_name);
    is $account->name, $new_name,
        'account name was changed after db round-trip';
    ok exception { $account->update(name => 'Socialtext') },
        'cannot rename account to an existing name';
    is $account->name, $new_name,
        'account name unchanged after attempt to duplicate rename';
}

SKIP: {
    eval { require Socialtext::People::Profile }
        or skip("The People plugin is not available!", 2);

    my $dummy3 = Socialtext::User->new( username => 'dummy3' );
    my $profile = Socialtext::People::Profile->GetProfile( $dummy3->user_id );
    $profile->is_hidden(1);
    $profile->save;

    users_are($test, [qw/dummy2/], 1, 1);

    $profile->is_hidden(0);
    $profile->save;
}

Account_skins: {
    # set skins
    my $ws      = $test->workspaces->next;
    my $ws_name = $ws->name;
    $ws->update(skin_name => 'reds3');
    my $ws_skin = $ws->skin_name;

    $test = Socialtext::Account->new(name => 'Test Account');
    is($test->skin_name, 's3', 'the default skin for accounts');

    $test->update(skin_name => 's2');
    is($test->skin_name, 's2', 'set the account skin');
    is(
        Socialtext::Workspace->new(name => $ws_name)->skin_name,
        $ws_skin,
        'updating account skin does not change workspace skins'
    );
    my $new_test = Socialtext::Account->new(name => 'Test Account');
    is($new_test->skin_name, 's2', 'set the account skin');

    # reset account and workspace skins
    $new_test->reset_skin('reds3');

    $test = Socialtext::Account->new(name => 'Test Account');
    is(
        $test->skin_name,
        'reds3',
        'reset_skin sets the skins of account workspaces'
    );
    is(
        Socialtext::Workspace->new(name => $ws_name)->skin_name,
        '',
        'reset_skin sets the skins of account workspaces'
    );

    eq_or_diff( [], $test->custom_workspace_skins, 'custom workspace skins is empty.');
    $ws->update( skin_name => 's3' );
    eq_or_diff( ['s3'], $test->custom_workspace_skins, 'custom workspace skins updated.');
    my $mess = $test->custom_workspace_skins( include_workspaces => 1 );
    is( $ws_name, $mess->{s3}[0]{name}, 'custom skins with workspaces.');
}

use Test::MockObject;
my $mock_adapter = Test::MockObject->new({});
$mock_adapter->mock('hook', sub {});
my $mock_hub = Test::MockObject->new({});
$mock_hub->mock('pluggable', sub { $mock_adapter });

ok $test->logo->is_default, 'logo is default';

my $logo_ref;
Set_a_logo: {
    my $orig_logo = Socialtext::File::get_contents_binary(
        "t/test-data/discoverppl.jpg");
    ok !exception { $test->logo->set(\$orig_logo) }, 'set the account logo';
    $logo_ref = $test->logo->logo;
    ok $logo_ref, 'logo ref was set';
    ok !$test->logo->is_default, 'logo is no longer the default';
}

Load_a_logo: {
    my $account = Socialtext::Account->new(name => $test->name);
    my $blob_ref = $account->logo->logo();
    ok $blob_ref, 'able to reload logo';
    ok $$blob_ref eq $$logo_ref, '... identical to uploaded logo';
}

my $export_file;
Exporting_account_people: {
    $export_file = $test->export( dir => 't', hub => $mock_hub );
    ok -e $export_file, "exported file $export_file exists";
    my $data = LoadFile($export_file);
    is $data->{name}, 'Test Account', 'name is in export';
    is $data->{is_system_created}, 0, 'is_system_created is in export';
    is scalar(@{ $data->{users} }), 3, 'users exported in test account';
    my @users = sort { $a->{username} cmp $b->{username} } @{ $data->{users} };
    is $users[0]{username}, 'dummy1', 'user 1 username';
    is $users[0]{email_address}, 'devnull1@example.com', 'user 1 email';
    is $users[1]{username}, 'dummy2', 'user 2 username';
    is $users[1]{email_address}, 'devnull2@example.com', 'user 2 email';
    is $users[2]{username}, 'dummy3', 'user 3 username';
    is $users[2]{email_address}, 'devnull3@example.com', 'user 3 email';

    {
        use bytes;
        ok $data->{logo}, 'logo was exported';
        my $exported_logo = MIME::Base64::decode($data->{logo});
        ok $$logo_ref eq $exported_logo, 'exported the correct image';
    }
}

# Now blow the account and users away for the re-import
Test::Socialtext::User->delete_recklessly( Socialtext::User->Resolve('dummy1') );
Test::Socialtext::User->delete_recklessly( Socialtext::User->Resolve('dummy2') );

Import_account: {
    my $account = Socialtext::Account->import_file( 
        file => $export_file,
        name => 'Imported account',
        hub => $mock_hub,
    );
    is $account->name, 'Imported account', 'new name was set';
    is $account->workspace_count, 0, "import doesn't import workspace data";
    users_are($account, [qw/dummy1 dummy2 dummy3/]);

    my $imported_logo_ref = $account->logo->logo();
    ok $$imported_logo_ref eq $$logo_ref, 'logo identical on import';
}

Wierd_corner_case: {
    my $user = Socialtext::User->create(
            username      => "dummy1234",
            email_address => "devnull1234\@example.com",
            password      => 'password',
            primary_account_id => $unknown->account_id
    );
    isa_ok($user, 'Socialtext::User');
    $ws->add_user( user => $user );
    is($user->primary_account->name, $test->name);
}

Plugins_enabled_for_all: {
    Socialtext::Account->DisablePluginForAll('testplugin');

    my $account1 = Socialtext::Account->create(name => "new_account_$^T");
    ok !$account1->is_plugin_enabled('testplugin'),
       'testplugin is not enabled by default';

    Socialtext::Account->EnablePluginForAll('testplugin');
    ok Socialtext::SystemSettings::get_system_setting('testplugin-enabled-all'),
       'System entry created for enabled plugin';
    ok $account1->is_plugin_enabled('testplugin'),
        'testplugin is now after EnablePluginForAll';

    my $account2 = Socialtext::Account->create(name => "newer_account_$^T");
    ok $account2->is_plugin_enabled('testplugin'),
       'testplugin is enabled for new accounts after EnablePluginForAll';
}

account_has_user_primary_account: {
    my $account_one = create_test_account_bypassing_factory();
    my $account_two = create_test_account_bypassing_factory();
    my $user_one    = create_test_user(account => $account_one);
    my $user_two    = create_test_user(account => $account_two);

    ok  $account_one->has_user($user_one), 'Account contains User';
    ok !$account_one->has_user($user_two), '... but not this other User';
}

account_has_user_secondary_account: {
    my $account_one = create_test_account_bypassing_factory();
    my $account_two = create_test_account_bypassing_factory();
    my $user_one    = create_test_user(account => $account_one);
    my $user_two    = create_test_user(account => $account_two);
    my $workspace   = create_test_workspace(account => $account_one);
    $workspace->add_user(user => $user_two);

    ok $account_one->has_user($user_one), 'Account contains User (which is his Primary Account)';
    ok $account_one->has_user($user_two), '... and this other User (which is a Secondary Account)';
}

Account_types: {
    my $account_one = create_test_account_bypassing_factory();
    is $account_one->account_type, 'Standard', 'account_type';
    my $workspace = create_test_workspace(account => $account_one);
    is $workspace->invitation_filter, undef,        'no invitation filter';

    # Set it up like a free 50: email restriction & no socialcalc
    $account_one->update(account_type => 'Free 50');
    is $account_one->account_type,    'Free 50', 'account_type';
    $workspace = Socialtext::Workspace->new(name => $workspace->name); #reload
    $workspace->update(invitation_filter => 'socialtext.net');
    is $workspace->invitation_filter, 'socialtext.net',        'invitation filter set to socialtext.net';
    ok $workspace->email_passes_invitation_filter('me@socialtext.net'), 'me@socialtext.net passes';
    ok $workspace->email_passes_invitation_filter('me@SOCIALTEXT.NET'), 'me@SOCIALTEXT.NET passes';
    ok !$workspace->email_passes_invitation_filter('socialtext@example.com'), 'socialtext@exmaple.com does not pass';
    is $workspace->is_plugin_enabled('socialcalc'), 0, 'socialcalc enabled';

    $account_one->update(account_type => 'Paid'); # or any type, really
    $workspace = Socialtext::Workspace->new(name => $workspace->name); #reload
    is $account_one->account_type, 'Paid', 'account_type';
    is $workspace->invitation_filter, '',        'no invitation filter';
    is $workspace->is_plugin_enabled('socialcalc'), 1, 'socialcalc enabled';
}

restrict_to_domain: {
    my $account = create_test_account_bypassing_factory();

    # valid domain.
    ok !exception { $account->update(restrict_to_domain => 'socialtext.com') },
        'updated restrict_to_domain with valid value';

    ok $account->email_passes_domain_filter('me@socialtext.com'), 'me@socialtext.com passes';
    ok $account->email_passes_domain_filter('me@SOCIALTEXT.COM'), 'me@SOCIALTEXT.COM passes';
    ok !$account->email_passes_domain_filter('socialtext.com@example.com'), 'socialtext.com@example.com does not pass';

    # invalid domain.
    like exception { $account->update(restrict_to_domain => 'valid!@.com') },
        qr/is not valid/, 'restrict_to_domain has invalid value';

    # remove restriction
    ok !exception { $account->update( restrict_to_domain => '' ); },
        'unsetting restrict_to_domain';
}

free50_accounts: {
    my $lookup = Socialtext::Account->Free50ForDomain('valid.com');
    ok ! $lookup, 'no Free 50 account found';

    my $acct = create_test_account_bypassing_factory();
    my $ws   = create_test_workspace( account => $acct );
    ok !exception {
        $acct->update(
            restrict_to_domain  => 'valid.com',
            account_type        => 'Free 50',
        );
        $ws->add_account(account => $acct);
    },;

    $lookup = Socialtext::Account->Free50ForDomain('valid.com');
    is $acct->account_id, $lookup->account_id, 'got correct Free 50 account';

    my $other    = create_test_account_bypassing_factory();
    my $other_ws = create_test_workspace( account => $other );
    ok !exception {
        $other->update(
            restrict_to_domain  => 'valid.com',
            account_type        => 'Free 50',
        );
        $other_ws->add_account(account => $other);
    },;

    $lookup = Socialtext::Account->Free50ForDomain('valid.com');

    # when two accounts have the same domain restriction, we should return the
    # one with the the smallest account_id; $lookup will _still_ equal $acct.
    is $lookup->account_id, $acct->account_id, 'got first Free 50 account'
}

exit;

sub users_are {
    my $account = shift;
    my $users = shift;
    my $primary_only = shift;
    my $exclude_hidden_people = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    # check user count
    # check user list

    my $count = $account->user_count(
        direct          => $primary_only,
        exclude_hidden_people => $exclude_hidden_people,
    );
    is $count, scalar(@$users), 
        $account->name . ' account has right number of users';

    for my $order_by (qw( username creation_datetime creator )) {
        my $mc = $account->users(
            direct => $primary_only,
            exclude_hidden_people => $exclude_hidden_people,
            order_by => $order_by,
        );
        is( join(',', sort map { $_->username } $mc->all), 
            join(',', sort @$users),
            $account->name . ' account users are correct' );
    }
}
