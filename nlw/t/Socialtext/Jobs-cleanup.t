#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 17;
use Test::Socialtext::Fatal;
use Socialtext::SQL qw/:exec get_dbh/;

fixtures('db');

BEGIN {
    use_ok 'Socialtext::Jobs';
    use_ok 'Socialtext::JobCreator';
}

ok !exception {
    Socialtext::Jobs->clear_jobs();
}, 'cleared all jobs';

my $job_creator = Socialtext::JobCreator->instance;
ok $job_creator;
my $jobs = Socialtext::Jobs->instance;
ok $jobs;

cancel: {
    my $jh = $job_creator->insert(
        'Socialtext::Job::Test' => {test => 1, job => {uniqkey => "howdy$^T"}});

    ok $jobs->list_jobs({funcname => 'Socialtext::Job::Test'}), 'got at least one test job';

    $job_creator->cancel_job(
        {funcname => 'Socialtext::Job::Test', uniqkey => "howdy$^T"});

    $jobs->can_do('Socialtext::Job::Test');
    ok !$jobs->list_jobs({funcname => 'Socialtext::Job::Test'}),
        'test job got cancelled';

    ok !$jh->is_pending, 'job not pending';
    my $job = $jh->job; # get the result
    is $jh->exit_status => 0, 'job exited with status 0';
}

cleanup: {
    no warnings 'redefine';
    my $orig = \&Socialtext::Jobs::job_types;

    $job_creator->insert(
        'Socialtext::Job::Test' => {test => 42, job => {uniqkey => "roger$^T"}});
    $job_creator->insert(
        'Socialtext::Job::Other' => {test => 43});

    my $id = $jobs->funcname_to_id(get_dbh(), 'Socialtext::Job::Other');
    ok $id;

    ok $jobs->list_jobs({ funcname => 'Socialtext::Job::Test' }),
        'at least one test job';
    ok $jobs->list_jobs({ funcname => 'Socialtext::Job::Other' }),
        'and some other job';

    my @cleaned;
    ok !exception {
        $jobs->cleanup_job_tables(sub { push @cleaned, $_[0] });
    }, 'cleaned up tables';
    is_deeply \@cleaned, ['Socialtext::Job::Other'], 'just the other type';

    my $after_id = $jobs->funcname_to_id(get_dbh(), 'Socialtext::Job::Other');
    ok((!$after_id || $after_id != $id), 'funcmap entry cleared');

    ok $jobs->list_jobs({funcname => 'Socialtext::Job::Test'}),
        'test job still there';
    ok !$jobs->list_jobs({funcname => 'Socialtext::Job::Other'}),
        'other job is gone';
}
