#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 70;
fixtures(qw( clean db ));
use Socialtext::User;
use Socialtext::Role;
use Socialtext::SQL::Builder qw(sql_abstract);
use Socialtext::SQL qw(sql_execute);
use Test::Socialtext::Fatal;

my $user;

is( Socialtext::User->Count(), 2, 'base users are registered' );
ok( Socialtext::User->SystemUser, 'a system user exists' );
ok( Socialtext::User->Guest, 'a guest user exists' );
is( Socialtext::User->Guest->primary_account->name, 'Socialtext',
    'Guest user has correct account' );

$user = Socialtext::User->new( username => 'devnull9@socialtext.net', );
is( $user, undef, 'no non-special users exist yet' );

$user = Socialtext::User->SystemUser;

is( $user->driver_name, 'Default',
    'System User is stored in Postgres (Default).'
);

is( $user->creator->username, 'system-user',
    'System User sprang from suigenesis.'
);
is( $user->primary_account->name, 'Socialtext',
    'System user has correct account',
);

my $new_user = Socialtext::User->create(
    username      => 'devnull1@socialtext.com',
    first_name    => 'Dev',
    last_name     => 'Null',
    email_address => 'devnull1@socialtext.com',
    password      => 'd3vnu11l'
);
$new_user->set_technical_admin(1);

is( $new_user->creator->username, 'system-user',
    'Unidentified creators default to system-user.'
);

my $newer_user = Socialtext::User->create(
    username           => 'devnull2@socialtext.com',
    first_name         => 'Dev',
    last_name          => 'Null 2',
    email_address      => 'devnull2@socialtext.com',
    password           => 'password',
    created_by_user_id => $new_user->user_id
);

is( $newer_user->creator->username, 'devnull1@socialtext.com',
    'Tracking creator.'
);

ok( $newer_user->password_is_correct( 'password' ),
    'Password checks out.'
);

ok( $newer_user->update_store( last_name => 'Nullius' ),
    'Can update certain data (like last name).'
);

is( $newer_user->last_name, 'Nullius',
    'And when updated, the instance retains the new value' );

ok( !$newer_user->is_business_admin,
    "By default, users aren't business admins" );

ok( $newer_user->set_business_admin(1), "But they can be made to be." );

ok( $newer_user->is_business_admin(),
    "And when they are, the instance is updated." );

my $user3 = Socialtext::User->create(
    username      => 'nonauth@socialtext.net',
    email_address => 'nonauth@socialtext.net',
    password      => 'unencrypted',
    no_crypt      => 1,
    created_by_user_id => $user->user_id,
);

$user3->create_email_confirmation;

ok $user3->requires_email_confirmation, 'user requires email confirmation';

account_roles_for_created_user: {
    my $member         = Socialtext::Role->Member();
    my $base_id        = time . $$;
    my $account        = Socialtext::Account->Default();
    my $custom_account = create_test_account_bypassing_factory();

    # Using the default account
    my $default_user_email = "$base_id-default\@socialtext.net";
    my $default_user = Socialtext::User->create(
        username      => $default_user_email,
        email_address => $default_user_email,
        password      => 'unencrypted',
        no_crypt      => 1,
        created_by_user_id => $user->user_id,
    );
    my $role = $account->role_for_user($default_user);

    ok $role, 'newly created user has role in default account';
    is $role->role_id, $member->role_id, '... role is member';

    # Using a custom account
    my $custom_user_email = "$base_id-custom\@socialtext.net";
    my $custom_user = Socialtext::User->create(
        username      => $custom_user_email,
        email_address => $custom_user_email,
        password      => 'unencrypted',
        no_crypt      => 1,
        created_by_user_id => $user->user_id,
        primary_account_id => $custom_account->account_id,
    );
    $role = $custom_account->role_for_user($custom_user);

    ok $role, 'newly created user has role in custom account';
    is $role->role_id, $member->role_id, '... role is member';
    ok !$account->has_user( $user ),
        'custom user does not have role in default account';
}

change_primary_account: {
    my $member  = Socialtext::Role->Member();
    my $account = Socialtext::Account->Default();
    my $email   = time . $$ . '-change-account@socialtext.com';
    my $user    = Socialtext::User->create(
        username           => $email,
        email_address      => $email,
        password           => 'unencrypted',
        no_crypt           => 1,
        created_by_user_id => $user->user_id,
    );

    my $role = $account->role_for_user($user);
    ok $role, 'user has role in default account';
    is $role->role_id, $member->role_id, '... role is member';

    my $other_account = create_test_account_bypassing_factory();
    $user->primary_account( $other_account );

    # Check default account role is preserved
    $role = $account->role_for_user($user);
    ok $role, 'user still has role in default account';
    is $role->role_id, $member->role_id, '... role is member';

    # Check for role in new account
    $role = $other_account->role_for_user($user);
    ok $role, 'user still has role in default account';
    is $role->role_id, $member->role_id, '... role is member';
}

email_hiding_by_account :
{
    my $visible_account = Socialtext::Account->create(
        name => 'visible_account',
    );
    my $hidden_account = Socialtext::Account->create(
        name => 'hidden_account',
    );

    my $hidden_workspace = Socialtext::Workspace->create(
        name       => 'hidden_workspace',
        title      => 'Hidden Workspace',
        account_id => $hidden_account->account_id,
    );
    my $visible_workspace = Socialtext::Workspace->create(
        name       => 'visible_workspace',
        title      => 'visible Workspace',
        account_id => $visible_account->account_id,
    );

    $hidden_account->update(email_addresses_are_hidden => 1);
    $hidden_workspace->update(email_addresses_are_hidden => 1);

    my $personA = Socialtext::User->create(
        username           => 'person.a@socialtext.com',
        first_name         => 'Person',
        last_name          => 'A',
        email_address      => 'person.a@socialtext.com',
        password           => 'password',
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $hidden_account->account_id,
    );

    my $personB = Socialtext::User->create(
        username           => 'person.b@socialtext.com',
        first_name         => 'Person',
        last_name          => 'B',
        email_address      => 'person.b@socialtext.com',
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $hidden_account->account_id,
    );

    is $personA->masked_email_address(user => $personB),
       'person.a@hidden',
       'primary = hidden == hidden';
    is $personB->masked_email_address(user => $personA),
       'person.b@hidden',
       'primary = hidden == hidden';

    # primary = hidden + visible == visible
    $visible_account->add_user( user => $personA );
    $visible_account->add_user( user => $personB );

    is $personA->masked_email_address(user => $personB),
       'person.a@socialtext.com',
       'primary = hidden + visible == visible';
    is $personB->masked_email_address(user => $personA),
       'person.b@socialtext.com',
       'primary = hidden + visible == visible';

    # remove the users' membership from the account so we can test a secondary
    # relationship.
    $visible_account->remove_user( user => $personA );
    ok !$visible_account->has_user( $personA );

    $visible_account->remove_user( user => $personB );
    ok !$visible_account->has_user( $personB );

    # primary = hidden + secondary = visible == visible

    $visible_workspace->add_user(user => $personA);
    $visible_workspace->add_user(user => $personB);

    is $personA->masked_email_address(user => $personB),
       'person.a@socialtext.com',
       'primary = hidden + secondary = visible == visible';
    is $personB->masked_email_address(user => $personA),
       'person.b@socialtext.com',
       'primary = hidden + secondary = visible == visible';

    # primary = visible + secondary = visible == visible

    $personA->primary_account($visible_account->account_id);
    $personB->primary_account($visible_account->account_id);

    is $personA->masked_email_address(user => $personB),
       'person.a@socialtext.com',
       'primary = visible == visible';
    is $personB->masked_email_address(user => $personA),
       'person.b@socialtext.com',
       'primary = visible == visible';

    # primary = visible + secondary = visible == visible

    $visible_workspace->remove_user(user => $personA);
    $visible_workspace->remove_user(user => $personB);

    is $personA->masked_email_address(user => $personB),
       'person.a@socialtext.com',
       'primary = visible + secondary = visible == visible';
    is $personB->masked_email_address(user => $personA),
       'person.b@socialtext.com',
       'primary = visible + secondary = visible == visible';
}

deactivate_user: {
    my $deleted = Socialtext::Account->Deleted();

    # create a user in a new account
    my $account = Socialtext::Account->create(name => "fuzz");
    my $user = Socialtext::User->create(
        username      => 'ronnie@ken.socialtext.net',
        first_name    => 'Dev',
        last_name     => 'Null',
        email_address => 'ronnie@ken.socialtext.net',
        password      => 'd3vnu11l'
    );
    $user->primary_account($account);
    is $account->user_count(), 1, "account has correct number of users";
    ok not $user->is_deactivated;

    # add them to some workspaces
    my $ws0 = Socialtext::Workspace->create(
        name       => 'workspace0',
        title      => 'Workspace0',
        account_id => $account->account_id,
    );
    $ws0->add_user(user => $user);
    my $ws1 = Socialtext::Workspace->create(
        name       => 'workspace1',
        title      => 'Workspace1',
        account_id => $account->account_id,
    );
    $ws1->add_user(user => $user);
    is $user->workspace_count(), 2, "user is in correct number of workspaces";

    # deactivate them
    $user->deactivate;
    ok $user->is_deactivated;

    # Check account membership
    my @accounts = $user->accounts();
    is scalar(@accounts), 1, 'deactivated user is in one account';
    is $user->primary_account_id, $deleted->account_id,
        "user's primary account is Deleted account";
    ok $deleted->has_user( $user ), 'user has a role in deleted account';

    # Check workspaces, password
    is $user->workspace_count(), 0, "user was removed from their workspaces";
    is $user->password, '*no-password*', "user's password was 'deactivated'";

    # "Reactivate" the user
    my $new_account = create_test_account_bypassing_factory();
    $user->reactivate( account => $new_account );

    # Check user account membership
    ok !$user->is_deactivated(), 'user was reactivated';
    ok !$deleted->has_user( $user ), 'user is not in deleted account';
    ok $new_account->has_user( $user ), 'user is in new account';
    is $new_account->account_id, $user->primary_account_id,
        '... which is their primary account';

    # purge the user's roles, confirm we can still deactivate
    Socialtext::UserSet->new->remove_set($user->user_id, roles_only => 1);

    ok !exception { $user->deactivate() }, 'can deactivate after accidental purge';
    ok $deleted->has_user($user), 'user has a role in deleted account';
    ok !$new_account->has_user($user), 'user removed from old account';
}

user_workspaces: {
    # create a user in a new account
    my $account = Socialtext::Account->create(name => "lookups");
    my $user = Socialtext::User->create(
        username      => 'findme@ken.socialtext.net',
        first_name    => 'Dev',
        last_name     => 'Null',
        email_address => 'findme@ken.socialtext.net',
        password      => 'd3vnu11l'
    );
    $user->primary_account($account);

    # add them to some workspaces
    my @to_create = ( 'lookupaaa', 'lookupbbb', 'lookupccc' );
    for my $name ( @to_create ) {
        my $ws = Socialtext::Workspace->create(
            name       => $name,
            title      => "Lookups $name",
            account_id => $account->account_id,
        );
        $ws->add_user(user => $user);
    }

    my @names = map { $_->name } 
        $user->workspaces()->all();
    is_deeply \@names, \@to_create, 'correct workspaces in correct order';

    @names = map { $_->name } 
        $user->workspaces( limit => 1 )->all();
    is $names[0],  'lookupaaa', 'correct limit';

    @names = map { $_->name }
        $user->workspaces( limit => 2, offset => 1 )->all();
    is_deeply \@names, [ 'lookupbbb', 'lookupccc' ], 'correct limit and offset';

}

###############################################################################
# TEST: ST::User doesn't trigger load of ST::Workspace (as that causes a ton
# of stuff to get pulled in, which makes ST::User prohibitively expensive to
# use).
dont_load_workspace: {
    my $loaded = modules_loaded_by('Socialtext::User');
    ok  $loaded->{'Socialtext::User'}, 'ST::User loaded';
    ok !$loaded->{'Socialtext::Workspace'}, '... ST::Workspace lazy-loaded';
}

AllTechnicalUsers: {
    my $users = Socialtext::User->AllTechnicalAdmins();
    is $users->count, 1, 'found 1 technical user!';
}

# TEST: to_hash() interface
to_hash: {
    my $private_id = Test::Socialtext->create_unique_id();
    my $user       = create_test_user(private_external_id => $private_id);

    # List of fields we expect in each of the hash reprs
    my @minimal_fields = qw(
        user_id username best_full_name display_name
    );
    my @standard_fields = qw(
        user_id username email_address password
        first_name middle_name last_name display_name
        creation_datetime last_login_datetime
        email_address_at_import created_by_user_id
        is_business_admin is_technical_admin is_system_created
        primary_account_id
    );
    my @with_private_fields = (
        @standard_fields,
        qw(
            private_external_id
        )
    );

    # Helper method to build the hash repr for the User
    my $make_hash = sub {
        my $user   = shift;
        my @fields = @_;
        my $data   = { map { $_ => $user->$_() } @fields };
        $data->{creator_username}     = $user->creator->username;
        $data->{primary_account_name} = $user->primary_account->name;
        return $data;
    };

    # Minimal
    minimal: {
        my $data   = $user->to_hash(minimal => 1);
        my $expect = { map { $_ => $user->$_() } @minimal_fields };
        is_deeply $data, $expect, 'Minimal hash repr for User';
    }

    # Standard
    standard: {
        my $data   = $user->to_hash();
        my $expect = $make_hash->($user, @standard_fields);
        is_deeply $data, $expect, 'Standard hash repr for User';
    }

    # With Private Fields
    with_private_fields: {
        my $data   = $user->to_hash(want_private_fields => 1);
        my $expect = $make_hash->($user, @with_private_fields);
        is_deeply $data, $expect, 'Extended/private hash repr for User';
    }
}

reload: {
    my $user      = create_test_user();
    my $old_email = $user->email_address;
    my $new_email = Test::Socialtext->create_unique_id . '@ken.socialtext.net';

    # manually update the DB, faking an update that we want to reload
    my ($sth, @bind) = sql_abstract->update(
        'users',
        { email_address => $new_email },
        { email_address => $old_email },
    );
    sql_execute($sth, @bind);

    ($sth, @bind) = sql_abstract->update(
        '"UserMetadata"',
        { email_address_at_import => $new_email },
        { email_address_at_import => $old_email },
    );
    sql_execute($sth, @bind);

    # Verify the old values are in the User object
    is $user->email_address,           $old_email, '... old e-mail in homey';
    is $user->email_address_at_import, $old_email, '... old e-mail in metadata';

    # Reload the User object
    $user->reload;

    # Confirm that the new values are in the User object
    is $user->email_address,           $new_email, '... new e-mail in homey';
    is $user->email_address_at_import, $new_email, '... new e-mail in metadata';
}

pass 'done';
