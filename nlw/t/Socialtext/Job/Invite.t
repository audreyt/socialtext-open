#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Email::Send::Test;
use Socialtext::JobCreator;
use Socialtext::Jobs;
use Test::Socialtext tests => 16;

# We want a db, but _no_ ceq jobs.
fixtures( qw(db no-ceq-jobs) );

no warnings 'once';
$Socialtext::EmailSender::Base::SendClass = 'Test';

my $class = 'Socialtext::Job::Invite';
use_ok $class;

# Register workers
Socialtext::Jobs->can_do($class);

################################################################################
process_job: {
    # Clear the message queue
    Email::Send::Test->clear();

    my $account   = create_test_account_bypassing_factory();
    my $invitor   = create_test_user();

    # The recipient _must_ be in the account ( either with a primary or
    # secondary relationship ) in order to receive a notification.
    my $recipient = create_test_user( account => $account );

    my $account_name    = $account->name;
    my $recipient_email = $recipient->email_address;
    my $invitor_email   = $invitor->email_address;
    my $invitor_name    = $invitor->display_name;

    Socialtext::JobCreator->insert(
        $class,
        {
            account_id => $account->account_id,
            user_id    => $recipient->user_id,
            sender_id  => $invitor->user_id,
        }
    );

    # Ensure the User _is_ in the Account
    ok $account->has_user( $recipient ), 'User is in the Account';

    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, 'Got a job';

    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, '... job completed';
    is $job->exit_status => 0, '... ... successfully';
 
    my ($email) = Email::Send::Test->emails();
    ok $email, '... sent an email';

    # Verify message
    my $body = $email->body_raw;
    like $body, qr/username:\s+\Q$recipient_email\E/,
        '... ... to recipient';
    like $body, qr/<p>\s+Thanks,\s+<\/p>\s+<p>\s+\Q$invitor_name\E/,
       '... ... from sender';
    like $body, qr/join the \Q$account_name\E group/,
       '... ... into account';

    $job = Socialtext::Jobs->find_job_for_workers();
    ok !$job, '... no more jobs';
}

################################################################################
# TEST: Send an Account Invitation message to a User, who (when the job runs)
# is *not* a member of the Account. The timing of the removal is not
# important, we just need to make sure that the user is not in the Account
# when the job is run.
user_is_not_in_network: {
    # Clear the message queue
    Email::Send::Test->clear();

    my $account   = create_test_account_bypassing_factory();
    my $invitor   = create_test_user();
    my $recipient = create_test_user();

    my $account_name    = $account->name;
    my $recipient_email = $recipient->email_address;
    my $invitor_email   = $invitor->email_address;

    Socialtext::JobCreator->insert(
        $class,
        {
            account_id => $account->account_id,
            user_id    => $recipient->user_id,
            sender_id  => $invitor->user_id,
        }
    );

    # Ensure the User is not in the Account.
    ok !$account->has_user( $recipient ), 'User is not in the Account';

    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, 'Got a job';

    my $rc = Socialtext::Jobs->work_once($job);
    ok $rc, '... job completed';
    is $job->exit_status => 255, '... ... unsuccessfully';

    my ($email) = Email::Send::Test->emails();
    is $email => undef, '... no email sent';

    $job = Socialtext::Jobs->find_job_for_workers();
    ok !$job, '... no more jobs';
}

exit;
