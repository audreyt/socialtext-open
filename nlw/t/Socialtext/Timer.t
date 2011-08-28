#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::More tests => 19;
use Test::Socialtext::Fatal;
use mocked 'Time::HiRes';

# Note: This module uses a mocked Time::HiRes so that we can test with
# deterministic times.  The mocked Time::HiRes will return an ever
# incrementing number to make testing easier, and independent of system load.

BEGIN {
    use_ok 'Socialtext::Timer';
}

Basic_usage: {
    my $t = Socialtext::Timer->new;
    is $t->elapsed, 1, 'timer worked';
}
sub usleep {} 

Singleton_usage: {
    Socialtext::Timer->Reset();
    Socialtext::Timer->Start('funky');
    Socialtext::Timer->Start('unstopped');
    Socialtext::Timer->Stop('funky');
    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '5.000',
        "singleton times overall - $timings->{overall}";
    is $timings->{funky}, '2.000',
        "singleton times funky equals 2 - $timings->{funky}";
    is $timings->{unstopped}, '2.000',
        "single times unstopped equals 2 - $timings->{unstopped}";
}

Singleton_pause: {
    Socialtext::Timer->Reset();
    Socialtext::Timer->Start('pausable');
    Socialtext::Timer->Pause('pausable');
    Socialtext::Timer->Continue('pausable');
    Socialtext::Timer->Pause('pausable');
    Socialtext::Timer->Continue('pausable');
    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '7.000',
        "overall time correct - $timings->{overall}";
    is $timings->{pausable}, '3.000',
        "pausable time equals 1 - $timings->{pausable}";
}

Singleton_continue_means_start: {
    Socialtext::Timer->Reset();
    Socialtext::Timer->Continue('pausable');
    Socialtext::Timer->Pause('pausable');
    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '3.000',
        "overall time correct - $timings->{overall}";
    is $timings->{pausable}, '1.000',
        "pausable time equals 1.000 - $timings->{pausable}";
}

Singleton_continue_twice: {
    # basically just checking for lack of blow up when
    # we continue a timer that was never paused, but has
    # started
    Socialtext::Timer->Reset();
    Socialtext::Timer->Continue('pausable');
    Socialtext::Timer->Continue('pausable');
    my $timings = Socialtext::Timer->Report();
    is $timings->{pausable}, '2.000',
        "double continue did not blow up - $timings->{pausable}";
}

Singleton_pause_twice: {
    # basically just checking for lack of blow up when
    # we pause a timer that was already paused.
    Socialtext::Timer->Reset();
    Socialtext::Timer->Continue('pausable');
    Socialtext::Timer->Continue('pausable');
    Socialtext::Timer->Pause('pausable');
    Socialtext::Timer->Pause('pausable');
    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '5.000',
        "overall time equals 5 - $timings->{overall}";
    is $timings->{pausable}, '2.000',
        "pausable time equals 2 - $timings->{pausable}";
}

Time_this: {
    Socialtext::Timer->Reset();
    Socialtext::Timer::time_this {
        my $x = 1;
    } 'rock';
    like exception {
        Socialtext::Timer::time_this {
            die "what the";
        } 'rock';
    }, qr#what the at t/Socialtext/Timer.t#;

    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '5.000',
        "overall time equals 5 - $timings->{overall}";
    is $timings->{rock}, '2.000', "rock timings - $timings->{rock}";
}

Time_scope: {
    Socialtext::Timer->Reset();

    ok !exception {
        my $t = Socialtext::Timer::time_scope('kick_it');
        return 1;
    }, 'normal return';

    ok exception {
        my $t = Socialtext::Timer::time_scope('kick_it');
        die "ZOMG";
    }, 'exception';

    my $timings = Socialtext::Timer->Report();
    is $timings->{overall}, '5.000',
        "overall time equals 5 - $timings->{overall}";
    is $timings->{kick_it}, '2.000', "kick_it timings - $timings->{kick_it}";
}

exit;
