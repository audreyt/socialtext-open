#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;
use Socialtext::Authen;
use Socialtext::AppConfig;

fixtures('db');

###############################################################################
# By default, the username label is "Email Address"
default_username_label_is_email_address: {
    Socialtext::AppConfig->set( user_factories => 'Default' );
    my $label = Socialtext::Authen->username_label();
    is $label, 'Email Address:', 'default username label is found';
}

###############################################################################
# But if we're using any other user factories, its "Username"
non_default_username_label_is_username: {
    Socialtext::AppConfig->set( user_factories => 'Default;Default' );
    my $label = Socialtext::Authen->username_label();
    is $label, 'Username:', 'non-default username label is found';
}
