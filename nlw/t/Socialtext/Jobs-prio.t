#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 19;
use Test::Socialtext::Fatal;
use List::Util qw/shuffle/;

fixtures('db');

BEGIN {
    use_ok 'Socialtext::Jobs';
    use_ok 'Socialtext::JobCreator';
    use_ok 'Socialtext::Job::Test';
}

my $jobs = Socialtext::Jobs->instance;
ok !exception { $jobs->clear_jobs() }, "can clear jobs";

# Because TheSchwartz takes the top "N" jobs ordered by priority and then
# shuffles those, limit "N" to 1 for testing.
Socialtext::TheSchwartz->Limit_list_jobs(1);

Order_jobs: {
    my @jobs = Socialtext::Jobs->list_jobs(
        funcname => 'Socialtext::Job::Test',
    );
    is scalar(@jobs), 0, 'no jobs to start with';

    my @job_args = ('Socialtext::Job::Test' => test => 1);
    my @expected_prio = (5,4,3,2,1,undef,-1);
    my %job_map;
    for my $prio (shuffle(@expected_prio)) {
        my $jh = Socialtext::JobCreator->insert(
            @job_args, job => {priority => $prio});
        ok $jh;
        $job_map{$jh->jobid} = $prio;
    }

    for my $prio (@expected_prio) {
        $jobs->can_do('Socialtext::Job::Test');
        $jobs->work_once();
        my $actual_prio = $job_map{$Socialtext::Job::Test::Last_ID};
        is $actual_prio, $prio, 'prio '.($prio||'undef').' job';
    }
}

