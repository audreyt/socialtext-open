#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;
use Test::Socialtext::Fatal;
use Test::Socialtext tests => 8;
use File::Basename qw(basename);
use Socialtext::Jobs;
use Socialtext::JobCreator;
use Socialtext::Job::Upgrade::IndexOffice2007SignalAttachments;
use Socialtext::Signal;
use Socialtext::Upload;

fixtures(qw( db ));

# TEST: Office 2007 Signal Attachments get scheduled for re-index
schedule_for_reindex: {
    my $hub = create_test_hub();
    Test::Socialtext->main_hub($hub);

    # create Signal with *NO* Office 2007 attachments
    my $miss_file   = 't/Socialtext/File/stringify_data/sample.doc';
    my $miss_signal = create_signal_with_attachment(
        $hub->current_user, 'Miss', $miss_file,
    );
    ok $miss_signal, 'created "Miss" signal';

    # create Signal with Office 2007 attachments
    my $hit_file   = 't/Socialtext/File/stringify_data/sample.docx';
    my $hit_signal = create_signal_with_attachment(
        $hub->current_user, 'Hit', $hit_file,
    );
    ok $hit_signal, 'created "Hit" signal';

    # clear Ceq queue
    ok !exception { Socialtext::Jobs->clear_jobs() }, 'cleared out queued jobs';

    # run the upgrade job
    my $upgrade_job_type = 'Socialtext::Job::Upgrade::IndexOffice2007SignalAttachments';
    my $index_job_type   = 'Socialtext::Job::SignalIndex';
    Socialtext::Jobs->can_do($upgrade_job_type);
    Socialtext::Jobs->can_do($index_job_type);
    Socialtext::JobCreator->insert($upgrade_job_type);

    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, 'upgrade job was added to queue';

    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, 'upgrade job completed';
    is $job->exit_status, 0, '... successfully';

    # verify that we've got one SignalIndex job
    my @jobs = Socialtext::JobCreator->list_jobs(
        funcname => $index_job_type,
    );
    is @jobs, 1, 'right number of signal index jobs';

    # verify that the job is for the Signal w/Office 2007 attachments
    is $jobs[0]->arg->{signal_id}, $hit_signal->signal_id,
        '... with the correct signal id';
}



sub create_signal_with_attachment {
    my ($user, $body, $filename) = @_;
    my $upload = Socialtext::Upload->Create(
        filename      => basename($filename),
        temp_filename => $filename,
        creator       => $user,
    );
    my $attach = Socialtext::Signal::Attachment->new(
        attachment_id => $upload->attachment_id,
        upload        => $upload,
        signal_id     => 0,                        # placeholder
    );
    my $signal = Socialtext::Signal->Create(
        body        => $body,
        user        => $user,
        user_id     => $user->user_id,
        attachments => [$attach],
    );
    return $signal;
}
