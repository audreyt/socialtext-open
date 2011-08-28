#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 45;
use Test::Socialtext::Fatal;
use Test::Socialtext::Ceqlotron;

BEGIN {
    use_ok 'Socialtext::Jobs';
    use_ok 'Socialtext::JobCreator';
}

# failsafe:
END { ceq_kill() }

fixtures(qw( db no-ceq-jobs ));

my $Ceq_bin = ceq_bin();
ok -x $Ceq_bin;
ceq_config(
    period => 0.1,
    polling_period => 0.1,
    max_concurrency => 2,
);

Start_and_stop: {
    ceq_fast_forward();

    my $ceq_pid = ceq_start();

    my @startup = ceq_get_log_until(
        qr/Ceqlotron master: fork, concurrency now \d/);

    ok grep(qr/ceqlotron starting/,@startup), 'ceq logged startup msg';
    my @started_kids = grep /Ceqlotron worker: starting/, @startup;
    is scalar(@started_kids), 2, 'two workers started up';

    ok kill(0 => $ceq_pid), "ceq pid $ceq_pid is alive";

    Start_another_ceq: {
        system($Ceq_bin);
        ok $?, 'exited with an error';
        my $new_pid = qx($Ceq_bin --pid); chomp $new_pid;
        is $new_pid, $ceq_pid, 'ceq pid did not change';
    }

    ceq_fast_forward();

    ok kill(INT => $ceq_pid), "sent INT to $ceq_pid";
    my @shutdown = ceq_get_log_until(qr/master: exiting/);

    ok !kill(0 => $ceq_pid), "ceq pid $ceq_pid is no longer alive";

    my @stopped_kids = grep /Ceqlotron worker: exiting/, @shutdown;
    is scalar(@stopped_kids), 2, 'both workers shutdown';
}

Process_a_job: {
    ceq_fast_forward();
    my $ceq_pid = ceq_start();

    my @startup = ceq_get_log_until(
        qr/Ceqlotron master: fork, concurrency now \d/);

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test',
        { 
            message => 'no pun intended',
            sleep => 4,
            post_message => 'twss',
        },
    );

    ceq_fast_forward();
    ceq_get_log_until(qr/no pun intended/);

    # Now send the process SIGTERM, and it should start to exit
    ok kill(TERM => $ceq_pid), "sent TERM to $ceq_pid";

    my @shutdown = ceq_get_log_until(qr/master: exiting/);
    ok(grep(qr/caught SIGTERM/, @shutdown), 'see SIGTERM');
    ok(grep(qr/waiting for children to exit/, @shutdown), 'see "waiting"');
    ok(grep(qr/twss/, @shutdown), 'job got to finish, though');
}

Workers_are_limited: {
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test',
        { 
            message => "start-$_",
            sleep => 5,
            post_message => "end-$_",
        },
    ) for (0 .. 9);

    ceq_fast_forward();
    my $ceq_pid = ceq_start();

    # let some jobs start up
    sleep 3;

    # Now send the process SIGTERM, and it should start to exit
    ok kill(INT => $ceq_pid), "sent INT to $ceq_pid";

    my @lines = ceq_get_log_until(qr/master: exiting/);

    my @started = sort {$a<=>$b} map { /[^"]start-(\d)/ ? $1 : () } @lines;
    my @ended =   sort {$a<=>$b} map { /[^"]end-(\d)/   ? $1 : () } @lines;

    is scalar(@started), 2, 'just two jobs got to start';
    is scalar(@ended), 2, 'just two jobs got to end';
    is_deeply \@started, \@ended, "same jobs got started and ran to completion";
}

Once_mode: {
    my $NUM_JOBS = 50;
    Socialtext::Jobs->clear_jobs();
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test',
        { 
            message => "start-$_",
            sleep => 0,
            post_message => "end-$_",
        },
    ) for (1 .. $NUM_JOBS);
    my @start_with = Socialtext::Jobs->list_jobs(
        funcname => 'Socialtext::Job::Test'
    );
    is scalar(@start_with), $NUM_JOBS, 'start with a bunch of jobs';

    ceq_fast_forward();
    ok !exception {
        ceq_start('--foreground --once');
    }, 'ran ceqlotron in foreground in once mode';
    my @lines = ceq_get_log_until(qr/master: exiting/);

    my @leftovers = Socialtext::Jobs->list_jobs(
        funcname => 'Socialtext::Job::Test'
    );
    is scalar(@leftovers), 0, "no leftovers";

    my @started = sort {$a<=>$b} map { /[^"]start-(\d)/ ? $1 : () } @lines;
    my @ended =   sort {$a<=>$b} map { /[^"]end-(\d)/   ? $1 : () } @lines;
    is scalar(@started), $NUM_JOBS, "$NUM_JOBS started";
    is scalar(@ended), $NUM_JOBS, "$NUM_JOBS ended";
    is_deeply [grep /FAILED/, @lines], [], "no failed jobs";
    is_deeply [grep /TEMPFAILED/, @lines], [], "no tempfailed jobs";
    is_deeply \@started, \@ended, "same jobs got started and ran to completion";
}

Fail_and_tempfail: {
    Socialtext::Jobs->clear_jobs();
    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test', {fail => 1}
    );

    {
        local $ENV{TEST_JOB_RETRIES} = 1;
        ceq_fast_forward();
        ok !exception {
            ceq_start('--foreground --once');
        }, 'ran ceqlotron in foreground in once mode';
        my @lines = ceq_get_log_until(qr/master: exiting/);

        my @leftovers = Socialtext::Jobs->list_jobs(
            funcname => 'Socialtext::Job::Test'
        );
        is scalar(@leftovers), 1, "job will be retried";

        my @tempfailed = grep /TEMPFAILED/, @lines;
        is scalar(@tempfailed), 1, "one tempfail line";
    }

    {
        ceq_fast_forward();
        ok !exception {
            ceq_start('--foreground --once');
        }, 'ran ceqlotron in foreground in once mode';
        my @lines = ceq_get_log_until(qr/master: exiting/);

        my @leftovers = Socialtext::Jobs->list_jobs(
            funcname => 'Socialtext::Job::Test'
        );
        is scalar(@leftovers), 0, "job will not be retried";

        my @tempfailed = grep /FAILED/, @lines;
        is scalar(@tempfailed), 1, "one fail line";
    }
}

exit;

