#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
# Importing Test::Socialtext will cause it to create fixtures now, which we
# want to happen want to happen _after_ Test::Live stops any running
# Apache instances, and all we really need here is Test::More.
use Test::More;
use Socialtext::Workspace;

use YAML;

plan tests => 22;

my $live = Test::Live->new();
my $base_uri = $live->base_url;
$live->log_in();

# test a succesful provision of a new account, new workspace and new user
{
    my $workspace_id = "new-workspace2";

    $live->mech()->post(
        "$base_uri/admin/index.cgi", {
            action          => 'workspaces_create_full',
            Button          => 'Create',
            name            => $workspace_id,
            title           => 'New WS Title2',
            account_name    => 'New Account',
            user_email      => 'devnull5@socialtext.com',
            user_first_name => 'Devin',
            user_last_name  => 'Nullington',
            logo_uri        => 'http://www.google.com/intl/de_ALL/images/logo.gif',
        },
    );
    my $response_content = $live->mech()->content();

    like ($live->mech()->ct(), qr{text/x-yaml}, 'check that content type is text/x-yaml' );

    # validate the response
    my $response;
    eval {
        $response = Load( $response_content );
        ok( $response, 'bad response' );
    };
    is( $@, '', 'got parseable YAML from workspace_create_full' );

    # this test should have succeeded so we want to look for a status_code of 'ok'
    is( $response->{status}, 'ok', 'test request succeeded' );
    ok( $response->{administrator_confirmation_uri}, 'expect a UserEmailConfirmation URI' );

    # validate the work
    my $ws = Socialtext::Workspace->new( name => 'new-workspace2' );
    ok( $ws, 'created new workspace' );
    is( $ws->title(), 'New WS Title2', 'check new workspace title' );
    is( $ws->logo_uri(), 'http://www.google.com/intl/de_ALL/images/logo.gif',
        'check logo uri' );
    is( $ws->account()->name(), 'New Account',
        'check that new account was created and workspace is assigned to it' );

    my $user = Socialtext::User->new( email_address => 'devnull5@socialtext.com' );
    ok( $user, 'created new user' );
    is( $user->first_name(), 'Devin', 'check user first name' );
    is( $user->last_name(), 'Nullington', 'check user last name' );

    my $role = $ws->role_for_user($user);
    is( $role->name(), 'workspace_admin', 'new user is admin for new workspace' );
    ok( $user->requires_confirmation(), 'user requires confirmation' );
}

# test a failing provision due to duplicate workspace id
# we can use admin as our workspace id because our fixture above created it
{
    $live->mech()->post(
        "$base_uri/admin/index.cgi", {
            action          => 'workspaces_create_full',
            Button          => 'Create',
            name            => 'admin',
            title           => 'New WS Title2',
            account_name    => 'New Account',
            user_email      => 'devnull5@socialtext.com',
            user_first_name => 'Devin',
            user_last_name  => 'Nullington',
            logo_uri        => 'http://www.google.com/intl/de_ALL/images/logo.gif',
        },
    );
    my $response_content = $live->mech()->content();

    # validate the response
    my $response;
    eval {
        $response = Load( $response_content );
        ok( $response, 'bad response' );
    };
    is( $@, '', 'got parseable YAML from workspace_create_full' );

    is( $response->{status}, 'error', 'failing test should produce error' );
    is( $response->{error_code}, 'duplicate_workspace_error', 'error is duplicate_workspace_error' );
}

# test a failing provision due to missing field
# we can use admin as our workspace id because our fixture above created it
{
    $live->mech()->post(
        "$base_uri/admin/index.cgi", {
            action          => 'workspaces_create_full',
            Button          => 'Create',
            name            => 'admin',
            title           => 'New WS Title2',
            user_first_name => 'Devin',
            user_last_name  => 'Nullington',
            logo_uri        => 'http://www.google.com/intl/de_ALL/images/logo.gif',
        },
    );
    my $response_content = $live->mech()->content();

    # validate the response
    my $response;
    eval {
        $response = Load( $response_content );
        ok( $response, 'bad response' );
    };
    is( $@, '', 'got parseable YAML from workspace_create_full' );

    is( $response->{status}, 'error', 'failing test should produce error' );
    is( $response->{error_code}, 'data_validation_error', 'error is data_validation_error' );
}
