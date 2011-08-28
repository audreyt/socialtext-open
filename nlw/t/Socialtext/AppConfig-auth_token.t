#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext tests => 6;
use Socialtext::AppConfig;

fixtures(qw( base_config ));

###############################################################################
# Ignore warnings of attempts to set limits to less than recommended minimums.
$SIG{__WARN__} = sub { };

###############################################################################
# TEST: soft limit sets properly
soft_limit_sets_properly: {
    my $expected = 12345;
    Socialtext::AppConfig->set(auth_token_soft_limit => $expected);
    my $received = Socialtext::AppConfig->auth_token_soft_limit;
    is $received, $expected, 'Auth Token soft limit sets properly';
}

###############################################################################
# TEST: hard limit sets properly
hard_limit_sets_properly: {
    my $expected = 23456;
    Socialtext::AppConfig->set(auth_token_hard_limit => $expected);
    my $received = Socialtext::AppConfig->auth_token_hard_limit;
    is $received, $expected, 'Auth Token hard limit sets properly';
}

###############################################################################
# TEST: soft limit of "<=0" gets forced to "minimum 24h"
soft_limit_zero_forced_to_24h: {
    my $expected = 86400;
    my $received;

    Socialtext::AppConfig->set(auth_token_soft_limit => 0);
    $received = Socialtext::AppConfig->auth_token_soft_limit;
    is $received, $expected, "'Soft limit == 0' forced to 'minimum 24h'";

    Socialtext::AppConfig->set(auth_token_soft_limit => -100);
    $received = Socialtext::AppConfig->auth_token_soft_limit;
    is $received, $expected, "'Soft limit < 0' forced to 'minimum 24h'";
}

###############################################################################
# TEST: hard limit of "<=0" gets forced to "minimum 24h"
hard_limit_zero_forced_to_24h: {
    my $expected = 86400;
    my $received;

    Socialtext::AppConfig->set(auth_token_hard_limit => 0);
    $received = Socialtext::AppConfig->auth_token_hard_limit;
    is $received, $expected, "'hard limit == 0' forced to 'minimum 24h'";

    Socialtext::AppConfig->set(auth_token_hard_limit => -100);
    $received = Socialtext::AppConfig->auth_token_hard_limit;
    is $received, $expected, "'hard limit < 0' forced to 'minimum 24h'";
}
