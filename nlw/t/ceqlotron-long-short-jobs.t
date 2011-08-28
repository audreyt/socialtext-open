#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use List::MoreUtils qw(first_index);
use Test::Socialtext tests => 15;
use Test::Socialtext::Ceqlotron;
use Socialtext::JobCreator;
use Socialtext::Jobs;

fixtures(qw( db no-ceq-jobs ));

###############################################################################
# No matter what, shut Ceq down when we're done.
END { ceq_kill() }

###############################################################################
# Global Ceq config for this test...
ceq_config(
    period         => 0.1,
    polling_period => 0.1,
);

###############################################################################
# TEST: ensure that we've *always* got at least one Worker able to run long
# jobs.
at_least_one_worker_capable_of_running_long: {
    ceq_config(max_concurrency => 1);
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::LongLived', { sleep => 0.1 },
    );

    ceq_fast_forward();
    my $ceq_pid = ceq_start();

    # Let TheCeq run the jobs out of the queue, then kill it off
    my @lines = ceq_get_log_until(qr/worker: no jobs/);
    ok kill(INT => $ceq_pid), "killed TheCeq pid: $ceq_pid";

    # VERIFY: the long lived job was run
    my @longlived = grep { /test::longlived/i } @lines;
    ok @longlived, '... which can process long-lived jobs';

    # CLEANUP; clear out TheCeq queue
    Socialtext::Jobs->clear_jobs();
}

###############################################################################
# TEST: ensure that a Worker capable of running long-lived jobs is *also*
# capable of running short-lived jobs.
long_running_worker_can_run_short_jobs: {
    ceq_config(max_concurrency => 1);
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::LongLived', { sleep => 0.1 },
    );
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::ShortLived', { sleep => 0.1 },
    );

    ceq_fast_forward();
    my $ceq_pid = ceq_start();

    # Let TheCeq run the jobs out of the queue, then kill it off
    my @lines = ceq_get_log_until(qr/worker: no jobs/);
    ok kill(INT => $ceq_pid), "killed TheCeq pid: $ceq_pid";

    # VERIFY: both long+short jobs got run
    my @longlived = grep { /test::longlived/i } @lines;
    ok @longlived, '... which can process long-lived jobs';

    my @shortlived = grep { /test::shortlived/i } @lines;
    ok @shortlived, '... and which can process short-lived jobs';

    # Cleanup; clear out TheCeq queue
    Socialtext::Jobs->clear_jobs();
}

###############################################################################
# TEST: long-lived jobs don't stall the whole TheCeq queue.
long_jobs_dont_stall_entire_queue: {
    ceq_config(max_concurrency => 2);
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::LongLived', { sleep => 5 },
    ) for (0 .. 5);
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::ShortLived', { sleep => 0.1 },
    ) for (0 .. 20);

    ceq_fast_forward();
    my $ceq_pid = ceq_start();

    # Let TheCeq run the jobs out of the queue, then kill it off
    my @lines = ceq_get_log_until(qr/worker: no jobs/);
    ok kill(INT => $ceq_pid), "killed TheCeq pid: $ceq_pid";
    push @lines, ceq_get_log_until(qr/master: exiting/);

    # VERIFY: short-lived Jobs got run *while* long-lived Jobs were running;
    # even though we had more long-lived Jobs than we had workers, we managed
    # to have _some_ workers that were processing short-lived Jobs while a
    # long-lived one was running.

    # ... zero in on *just* those things that ran _while_ the long-lived job
    #     was running.
    my @interleave = grep { /lived job/ } @lines;
    my $idx_start  = first_index { /start long-lived/ } @interleave;
    my $idx_finish = first_index { /finish long-lived/ } @interleave;
    ok $idx_finish > 0, '... ran a long-lived job';

    splice @interleave, $idx_finish-1;
    splice @interleave, 0, $idx_start;

    # ... we better have had some short-lived jobs that ran here
    my $ran_short_lived = grep { /finish short-lived/ } @interleave;
    ok $ran_short_lived, '... and short-lived jobs ran simultaneously';

    # Cleanup; clear out TheCeq queue
    Socialtext::Jobs->clear_jobs();
}
