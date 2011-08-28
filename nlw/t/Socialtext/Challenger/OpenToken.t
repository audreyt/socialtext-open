#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::WebApp';
use mocked 'Apache::Cookie';
use mocked 'Socialtext::Log', qw(:tests);
use mocked 'Socialtext::Hub';
use POSIX qw();
use MIME::Base64;
use Crypt::OpenToken;
use Socialtext::Challenger::OpenToken;
use File::Slurp qw(write_file);
use Socialtext::User;
use Test::Socialtext tests => 30;

###############################################################################
# Create our test fixtures *OUT OF PROCESS* as we're using a mocked Hub.
BEGIN {
    my $rc = system('dev-bin/make-test-fixture --fixture db');
    $rc >>= 8;
    $rc && die "unable to set up test fixtures!";
}
fixtures(qw( db ));

###############################################################################
# TEST DATA
###############################################################################
our %data = (
    challenge_uri => 'http://www.google.com',
    password      => 'a66C9MvM8eY4qJKyCXKW+19PWDeuc3th',
);

###############################################################################
# invalid config available; declines processing
invalid_config_declines_processing: {
    # doesn't matter what User we hand through; it should fail always
    my $user   = Socialtext::User->SystemUser;
    my $config = "# invalid configuration file";

    my $rc = _issue_challenge(
        with_config => $config,
        with_user   => $user,
        with_token  => 0,
    );
    ok !$rc, 'challenge declined';

    # make sure an error was signalled
    my $app = Socialtext::WebApp->instance();
    $app->called_pos_ok(2, '_handle_error', '... error was signalled');
    my ($self, %args) = $app->call_args(2);
    is $args{'error'}, 'OpenToken configuration missing/invalid.',
        '... ... missing/invalid configuration';
}

###############################################################################
# authenticated, but not authorized; should show "unauthorized_workspace"
# error.
authenticated_but_not_authorized: {
    # the User here needs to *not* be a Guest in the Hub's WS context; making
    # it the System User is easiest.
    my $user = Socialtext::User->SystemUser;

    my $rc = _issue_challenge(
        with_user  => $user,
        with_token => 0,
    );
    ok !$rc, 'challenge failed';

    # make sure the error was signalled
    my $app = Socialtext::WebApp->instance();

    $app->called_pos_ok(2, '_handle_error', '... error was signalled');
    my ($self, %args) = $app->call_args(2);
    is $args{'error'}{'type'}, 'unauthorized_workspace',
        '... ... unauthorized_workspace';
}

###############################################################################
# authenticated as guest user; should be treated as "not authenticated" and
# redirect the user off to the challenge_uri.
authenticated_as_guest_user: {
    my $user = Socialtext::User->Guest;

    my $rc = _issue_challenge(
        with_user  => $user,
        with_token => 0,
    );
    ok $rc, 'challenge was successful';

    # make sure a redirect was called (don't care to where, just so long as we
    # did a redirect instead of signalling an error)
    my $app = Socialtext::WebApp->instance();
    $app->called_ok('redirect', '... redirect was issued');
}

###############################################################################
# redirects that are issued point to the challenge URI
redirect_to_challenge_uri: {
    my $guard = Test::Socialtext::User->snapshot();
    my $user  = create_test_user();

    my $rc = _issue_challenge(
        with_user  => $user,
        with_token => 0,
    );
    ok $rc, 'challenge was successful';

    # make sure a redirect was issued to the 'challenge_uri'
    my $challenge_uri = Socialtext::OpenToken::Config->load->challenge_uri;
    my $webapp        = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    like $redirect_uri, qr/^$challenge_uri\?TARGET=/,
        '... redirecting to the challenge_uri';
}

###############################################################################
# expired/stale ticket
stale_ticket: {
    my $guard = Test::Socialtext::User->snapshot();
    my $user  = create_test_user();

    my $rc = _issue_challenge(
        with_user => $user,
        with_token => 1,
        with_token_data => {
            'not-before' => _make_iso8601_date(time + 86400),
        },
    );
    ok $rc, 'challenge was successful';

    # make sure we noted that the token was invalid
    logged_like 'info', qr/invalid token/, '... invalid token';

    # make sure a redirect was issued to the 'challenge_uri'
    my $challenge_uri = Socialtext::OpenToken::Config->load->challenge_uri;
    my $webapp        = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    like $redirect_uri, qr/^$challenge_uri\?TARGET=/,
        '... redirecting to the challenge_uri';
}

###############################################################################
# successful login sets the "user data cookie".
login_sets_user_data_cookie: {
    my $guard = Test::Socialtext::User->snapshot();
    my $user  = create_test_user();

    my $rc = _issue_challenge(
        with_user  => $user,
        with_token => 1,
    );
    ok $rc, 'challenge was successful';

    # verify that cookie was created
    my $count = Apache::Cookie->cookie_count();
    is $count, 1, 'HTTP cookie created';
}

###############################################################################
# Default redirection on successful login is "/".
default_redirect_is_root: {
    my $guard = Test::Socialtext::User->snapshot();
    my $user  = create_test_user();

    my $rc = _issue_challenge(
        with_user  => $user,
        with_token => 1,
    );
    ok $rc, 'challenge was successful';

    # verify that the redirect was to "/"
    my $webapp        = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    is $redirect_uri, '/', '... redirecting to "/"';
}

###############################################################################
# An "url" parameter containing a relative URL may be provided.
relative_url_is_allowed: {
    my $guard        = Test::Socialtext::User->snapshot();
    my $resource_url = '/relative/uri';
    my $user         = create_test_user();

    my $rc = _issue_challenge(
        with_user         => $user,
        with_token        => 1,
        with_resource_url => $resource_url,
    );
    ok $rc, 'challenge was successful';

    # verify that the redirect was to the target URI
    my $webapp = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    is $redirect_uri, $resource_url, '... redirecting to specified URL';
}

###############################################################################
# An "url" parameter containing a local absolute URL may be provided.
local_absolute_url_is_allowed: {
    my $guard        = Test::Socialtext::User->snapshot();
    my $hostname     = Socialtext::AppConfig->web_hostname();
    my $resource_url = '/absolute/uri';
    my $absolute_uri = "http://$hostname$resource_url";
    my $user         = create_test_user();

    my $rc = _issue_challenge(
        with_user         => $user,
        with_token        => 1,
        with_resource_url => $resource_url,
    );
    ok $rc, 'challenge was successful';

    # verify that the redirect was to the target URI
    my $webapp = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    is $redirect_uri, $resource_url, '... redirecting to (local) absolute URL';
}

###############################################################################
# An "url" parameter containing an external absolute URL is *NOT* allowed.
external_absolute_url_is_not_allowed: {
    my $guard        = Test::Socialtext::User->snapshot();
    my $hostname     = 'www.example.com';
    my $resource_url = '/absolute/uri';
    my $absolute_uri = "http://$hostname$resource_url";
    my $user         = create_test_user();

    my $rc = _issue_challenge(
        with_user         => $user,
        with_token        => 1,
        with_resource_url => $absolute_uri,
    );
    ok $rc, 'challenge was successful';

    # verify that the redirect was to the *default* redirect URI; we don't
    # allow for redirects to an external absolute URI
    my $webapp        = Socialtext::WebApp->instance();
    my $redirect_uri  = $webapp->{redirect};
    is $redirect_uri, '/', '... redirecting to default redirect URI';

    # make sure we used the default redirect URI for the right reason
    logged_like 'error', qr/redirect attempted to external/,
        '... ... and error was logged indicating why';
}

###############################################################################
# "challenge_uri" with query form preserves query vars.
preserve_challenge_uri_query_params: {
    local $data{challenge_uri} = 'http://www.google.com?foo=bar';

    my $user = create_test_user();
    my $rc   = _issue_challenge(
        with_user  => $user,
        with_token => 0,
    );
    ok $rc, 'challenge was successful';

    # make sure a redirect was issued
    my $webapp       = Socialtext::WebApp->instance();
    my $redirect_uri = $webapp->{redirect};
    like $redirect_uri, qr/TARGET=/, '... containing TARGET';
    like $redirect_uri, qr/foo=bar/, '... preserving query params';
}

###############################################################################
# Valid tokens for unknown Users generate an error message.
valid_token_but_unknown_user: {
    my $user = Socialtext::User->Guest;
    my $rc   = _issue_challenge(
        with_user       => $user,
        with_token      => 1,
        with_token_data => {
            subject => 'this-user-does-not-exist-anywhere@ken.socialtext.net',
        },
    );
    ok !$rc, 'challenge was declined';

    # make sure an error was recorded
    my $app = Socialtext::WebApp->instance();
    $app->called_pos_ok(2, '_handle_error', '... error was thrown');
    my ($self, %args) = $app->call_args(2);
    like $args{'error'}, qr/valid token.*unknown user.*this-user-does-not/,
        '... ... about valid token but unknown user';
}

exit;








###############################################################################

sub _issue_challenge {
    my %args = @_;
    my $user          = $args{with_user};
    my $config_text   = $args{with_config};
    my $with_token    = $args{with_token};
    my $resource_url  = $args{with_resource_url};
    my $challenge_uri = $args{with_challenge_uri};
    my $token_data    = $args{with_token_data} || {};

    # save the configuration, allowing for explicit over-ride of config text
    local $data{challenge_uri} = $challenge_uri if ($challenge_uri);
    my $config = Socialtext::OpenToken::Config->new(%data);
    Socialtext::OpenToken::Config->save($config);

    if ($config_text) {
        write_file(
            Socialtext::OpenToken::Config->config_filename,
            $config_text,
        );
    }

    # set the test user
    my $hub = Socialtext::Hub->new;
    $hub->{current_user} = $user;

    # cleanup prior to test run
    Socialtext::WebApp->clear_instance();
    Apache::Cookie->clear_cookies();
    clear_log();

    # create an OpenToken to use for the challenge
    my $token;
    if ($with_token) {
        my $password = decode_base64($data{password});
        my $factory  = Crypt::OpenToken->new(password => $password);
        $token = $factory->create(
            Crypt::OpenToken::CIPHER_AES128,
            {
                subject  => $user->username,
                %{$token_data},
            },
        );
    }
    my $token_param = $config->token_parameter;
    local $Apache::Request::PARAMS{$token_param} = $token;
    local $Apache::Request::PARAMS{redirect_to}  = $resource_url;

    # issue the challenge
    my $rc = Socialtext::Challenger::OpenToken->challenge(hub => $hub);
    return $rc;
}

sub _make_iso8601_date {
    my $time_t = shift;
    return POSIX::strftime('%Y-%m-%dT%H:%M:%SGMT', gmtime($time_t));
}
