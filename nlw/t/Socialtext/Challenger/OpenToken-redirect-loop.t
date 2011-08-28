#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use mocked 'Socialtext::Log', qw(:tests);
use mocked 'Socialtext::WebApp';
use Socialtext::AppConfig;
use Socialtext::OpenToken::Config;
use Socialtext::Challenger;
use Test::Socialtext tests => 5;

###############################################################################
# Create our test fixtures *OUT OF PROCESS* as we're using a mocked Hub.
BEGIN {
    my $rc = system('dev-bin/make-test-fixture --fixture db');
    $rc >>= 8;
    $rc && die "unable to set up test fixtures!";
}
fixtures(qw( db ));

###############################################################################
sub challenge_redirect_is($$$) {
    my $uri      = shift;
    my $expected = shift;
    my $msg      = shift;

    # Save the OpenToken config
    my $config = Socialtext::OpenToken::Config->new(
        challenge_uri => 'http://www.google.com',
        password      => 'a66C9MvM8eY4qJKyCXKW+19PWDeuc3th',
    );
    Socialtext::OpenToken::Config->save($config);

    # Set ourselves up to use OpenToken for the Challenge
    Socialtext::AppConfig->set(challenger => 'OpenToken');

    # Issue Challenge based on the requested URL
    Socialtext::WebApp->clear_instance();
    Socialtext::Challenger->Challenge(redirect => $uri);

    # Extract the "redirect_to" from the generated redirect
    my $webapp = Socialtext::WebApp->instance();

    my $redirect_uri    = $webapp->{redirect};
    my %redirect_params = URI->new($redirect_uri)->query_form;

    my $target_uri    = $redirect_params{TARGET};
    my %target_params = URI->new($target_uri)->query_form;

    my $redirect_to = $target_params{redirect_to};
    is $redirect_to, $expected, $msg;
}

###############################################################################
# Test various URLs to make sure that the final redirect URL is sane
challenge_redirect_is undef,           '/',             'Default redirect';
challenge_redirect_is '/',             '/',             'Root URL redirect';
challenge_redirect_is '/st/signals',   '/st/signals',   'Signals redirect';
challenge_redirect_is '/challenge',    '/',             '/challenge not ok';
challenge_redirect_is '/challenge-it', '/challenge-it', '/challenge in WS ok';
