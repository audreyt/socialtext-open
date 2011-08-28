#!perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 15;
use Test::Socialtext::Ceqlotron;
use Socialtext::AppConfig;

BEGIN {
    use_ok 'Socialtext::Job::Cmd';
    use_ok 'Socialtext::Jobs';
    use_ok 'Socialtext::JobCreator';
}
END { ceq_kill() }

ok(Socialtext::Job::Cmd->isa('Socialtext::Job'));

fixtures(qw( db no-ceq-jobs ));

my $Ceq_bin = ceq_bin();
ok -x $Ceq_bin;
ceq_config(
    period => 0.1,
    polling_period => 0.1,
    max_concurrency => 2,
);

touch_a_file: {
    ceq_fast_forward();

    my $touchfile    = Socialtext::AppConfig->test_dir() . "/job-cmd.$$";
    my $touch_handle = Socialtext::JobCreator->insert(
        'Socialtext::Job::Cmd',
        { 
            cmd => '/usr/bin/touch',
            args => [$touchfile],
        },
    );
    ok $touch_handle, 'inserted job';

    my $false_handle = Socialtext::JobCreator->insert(
        'Socialtext::Job::Cmd',
        { 
            cmd => '/bin/false',
        },
    );
    ok $false_handle, 'inserted job';

    my $ceq_pid = ceq_start();
    my @startup = ceq_get_log_until(
        qr/Ceqlotron master: fork, concurrency now/);

    sleep 1; # wait for kids to pick up the job
    kill(INT => $ceq_pid); # ask ceq to exit
    my @shutdown = ceq_get_log_until(qr/master: exiting/);
    
    is $touch_handle->exit_status, 0, 'touch job completed';
    ok -f $touchfile, "$touchfile exists";

    is $false_handle->exit_status, 256, 'false job failed';
    my @failures = $false_handle->failure_log;
    is_deeply \@failures, ['rc=256'], 'errors recorded correctly';
    my $false_job = $false_handle->job;
    ok !$false_job, 'false job failed permanently';
}

exit;
