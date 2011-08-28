#!/user/bin/perl
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Signal;
use Socialtext::Jobs;
use Socialtext::Job::SignalIndex;
use List::MoreUtils qw/any/;

use Test::Socialtext tests => 5;

$ENV{TEST_LESS_VERBOSE} = 1;
fixtures( qw(db no-ceq-jobs) );

use_ok 'Socialtext::Account::Transformer';

# Register workers
Socialtext::Jobs->can_do('Socialtext::Job::SignalIndex');

my $into_account = create_test_account_bypassing_factory();

################################################################################
simple: {
    my $old_account  = create_test_account_bypassing_factory();
    my $user         = create_test_user(account => $old_account);
    my $signal       = Socialtext::Signal->Create(
        body        => 'Super signal',
        user_id     => $user->user_id,
        account_ids => [ $old_account->account_id ],
    );
    ok $signal, 'created a signal';

    # for later
    my $signal_id = $signal->signal_id;

    my $transformer = Socialtext::Account::Transformer->new(
        into_account_name => $into_account->name);
    my $group = $transformer->acct2group(account_name => $old_account->name);

    my $job = Socialtext::Jobs->find_job_for_workers();
    ok $job && $job->funcname eq 'Socialtext::Job::SignalIndex',
        'got a signal index job for the signal';

    # freshen signal
    my $fresh = Socialtext::Signal->Get(
        viewer    => $user,
        signal_id => $signal_id
    );
    ok $fresh, 'found signal';

    my $in_group = any { $_ == $group->group_id } @{$fresh->group_ids};
    ok $in_group, 'signal has been moved to group';
}
