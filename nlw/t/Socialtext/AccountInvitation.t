#!/usr/bin/env perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 5;
use Email::Send::Test;
use Socialtext::Account;
use Socialtext::User;
use Socialtext::Jobs;
use Socialtext::Job::Invite;

BEGIN {
    use_ok( 'Socialtext::AccountInvitation' );
}

fixtures( qw(db no-ceq-jobs) );

$Socialtext::EmailSender::Base::SendClass = 'Test';

my $acct = create_test_account_bypassing_factory();
my $from = create_test_user( unique_id => 'invitor', account => $acct );

# Register worker
Socialtext::Jobs->can_do('Socialtext::Job::Invite');

Simple_case: {
    my $invitee_email = 'invitee@example.com';
    my $invitation = Socialtext::AccountInvitation->new(
        account   => $acct,
        from_user => $from,
    );

    eval { $invitation->queue($invitee_email); };
    my $e = $@;
    is $e, '', 'account invite sent';

    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job, 'got an invite job';

    my $invitee = Socialtext::User->new( email_address => $invitee_email );
    ok $invitee, 'user created';
    is $invitee->primary_account_id, $acct->account_id, 'user in correct acct';
}
