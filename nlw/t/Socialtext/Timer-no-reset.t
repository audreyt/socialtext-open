#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 6;
use mocked 'Time::HiRes';

BEGIN {
    use_ok 'Socialtext::Timer';
}

Singleton_no_reset: {
    Socialtext::Timer->Start('funky');
    Socialtext::Timer->Start('unstopped');
    Socialtext::Timer->Stop('funky');
    my $timings = Socialtext::Timer->Report();
    ok $timings->{funky} >= 1, 'singleton times funky over 1';
    ok $timings->{funky} <= 2, 'singleton times funky under 2';
    ok $timings->{unstopped} >=2, 'simgle times unstopped over 2';
    ok $timings->{unstopped} <=3, 'simgle times unstopped under 3';
    ok !exists($timings->{overall}), 'no overall timer is present';
}
