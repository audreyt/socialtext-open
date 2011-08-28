#!perl
# @COPYRIGHT@
use warnings;
use strict;

use Test::More tests => 25;
use Test::Socialtext::Async qw/empty_port/;
use Guard;

my $hostname = `hostname`; chomp $hostname;
$hostname =~ s/^[^.]*$/www.socialtext.net/;

my ($port,$sock) = empty_port();

use_ok 'AnyEvent::DNS';
use_ok 'Socialtext::Async::DNS'; # should happen *after* empty_port

no warnings 'once';

my $exec_counter = 0;
{
    no warnings 'redefine';
    no strict 'refs';
    # run once per UDP/TCP request:
    package Socialtext::Async::DNS;
    *{'Socialtext::Async::DNS::_exec'} = sub {
        my ($self,$req) = @_;
        $exec_counter++;
        $self->SUPER::_exec($req);
    }
}

my $resolver = AnyEvent::DNS::resolver();

resolver_is_reblessed: {
    ok exists($resolver->{st_cache}), 'resolver has a cache member var';
    ok exists($resolver->{st_pending}), 'resolver has a pending member var';
    isa_ok $resolver, 'Socialtext::Async::DNS';
}

two_in_parallel: {
    scope_guard { $resolver->clear_cache; $exec_counter=0 };
    my $cv = AE::cv;
    $cv->begin;
    my @results;
    for my $i (0..1) {
        $cv->begin;
        AnyEvent::DNS::a($hostname,sub {
            $results[$i] = [@_];
            $cv->end;
        });
    }
    $cv->end;
    $cv->recv;
    ok scalar(@{$results[0]}), 'got a result';
    ok scalar(@{$results[1]}), 'got a second result';
    is_deeply $results[0][0], $results[1][0], 'same answer in both';
    is $exec_counter, 1, "only one network request";
    ok exists $resolver->{st_cache}{$hostname}{a}, "cached";
}

two_in_sequence: {
    scope_guard { $resolver->clear_cache; $exec_counter=0 };
    my @results;

    for (0..1) {
        my $cv = AE::cv;
        AnyEvent::DNS::a($hostname,sub { $cv->send(\@_) });
        push @results, $cv->recv;
    }

    ok scalar(@{$results[0]}), 'got a result';
    ok scalar(@{$results[1]}), 'got a second result';
    is_deeply $results[0][0], $results[1][0], 'same answer in both';
    is $exec_counter, 1, "only one network request";
    ok exists $resolver->{st_cache}{$hostname}{a}, "cached";
}

two_in_sequence_full_disable: {
    local $Socialtext::Async::DNS::EnableCache = 0;
    scope_guard { $resolver->clear_cache; $exec_counter=0 };
    my @results;

    for (0..1) {
        my $cv = AE::cv;
        AnyEvent::DNS::a($hostname,sub { $cv->send(\@_) });
        push @results, $cv->recv;
    }

    ok scalar(@{$results[0]}), 'got a result';
    ok scalar(@{$results[1]}), 'got a second result';
    is_deeply $results[0][0], $results[1][0], 'same answer in both';
    is $exec_counter, 2, "two net requests";
    ok !exists $resolver->{st_cache}{$hostname}{a}, "NOT cached";
}

three_in_sequence_forced_expiry: {
    local $Socialtext::Async::DNS::EnableCache = 1;
    local $Socialtext::Async::DNS::RespectTTL = 0;
    local $Socialtext::Async::DNS::DefaultTTL = 2.0;
    scope_guard { $resolver->clear_cache; $exec_counter=0 };
    my @results;

    # first request stores in cache, second request gets cache hit, third
    # requests sees that cache has expired and goes to fetch it again.
    for (0..2) {
        sleep 3 if $_ == 2;
        AE::now_update;
        my $cv = AE::cv;
        AnyEvent::DNS::a($hostname,sub { $cv->send(\@_) });
        push @results, $cv->recv;
    }

    is_deeply $results[0][0], $results[1][0], 'same answer in both 0 and 1';
    is_deeply $results[0][0], $results[2][0], 'same answer in both 0 and 2';
    is $exec_counter, 2, "two net requests";
    is scalar @{$resolver->{st_cache}{$hostname}{a}}, 1, "just one cache entry";
}

pass 'done';
