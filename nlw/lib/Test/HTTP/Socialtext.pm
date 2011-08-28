package Test::HTTP::Socialtext;
# @COPYRIGHT@

use strict;
use warnings;
use base 'Test::HTTP';
use Class::Field;
use Test::Socialtext::User;

our $Live;

{
    no warnings 'once';
    $Test::HTTP::BasicUsername        = Test::Socialtext::User->test_username();
    $Test::HTTP::BasicPassword        = Test::Socialtext::User->test_password();
    $Test::HTTP::Syntax::Test_package = 'Test::HTTP::Socialtext';
}

sub import {
    my $caller = caller;
    # This is required to work around Test::Base's repeated mutilation of
    # Test::Builder->exported_to. -mml
    no warnings 'redefine';
    *Test::Builder::exported_to = sub { $caller };
    goto &Test::HTTP::import;
}

sub live {
    $Live ||= Test::Live->new;
    return $Live;
}

sub url { join '', live()->base_url, @_[1..$#_] }

1;
