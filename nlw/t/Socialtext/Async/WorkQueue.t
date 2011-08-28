#!perl
use warnings;
use strict;
# @COPYRIGHT@
use Test::More tests => 53;
use Test::Differences;
use AnyEvent;
use Coro;
use Coro::AnyEvent;

use ok 'Socialtext::Async::WorkQueue';

empty: {
    my $q = Socialtext::Async::WorkQueue->new(
        name => 'empty',
        cb => sub { },
    );
    ok $q;
    is $q->size, 0, "initially empty";
    eval { $q->shutdown };
    ok !$@, "shutdown ok";
}

normal: {
    my $expect_q1 = 0;
    my @order1;
    my $q1; $q1 = Socialtext::Async::WorkQueue->new(
        name => 'queue one',
        prio => Coro::PRIO_HIGH(),
        cb => sub {
            my $n = shift;
            cede if rand > 0.2;
            push @order1, "one $n";
            is $q1->size, $expect_q1, "one $n";
            $expect_q1--;
        },
    );
    ok $q1;

    my $expect_q2 = 0;
    my @order2;
    my $q2; $q2 = Socialtext::Async::WorkQueue->new(
        name => 'queue two',
        prio => Coro::PRIO_LOW(),
        cb => sub {
            my $n = shift;
            cede if rand > 0.9;
            push @order2, "two $n";
            is $q2->size, $expect_q2, "two $n";
            $expect_q2--;
        },
    );
    ok $q2;
    cede if rand > 0.3;
    ok !@order1;
    ok !@order2;

    for my $x (1..5) {
        $q1->enqueue([$x]);
        $expect_q1++;
        is $q1->size, $expect_q1, "check q1 size num $x";
        cede if rand > 0.5;
        $q2->enqueue([$x]);
        $expect_q2++;
        is $q2->size, $expect_q2, "check q2 size num $x";
        cede if rand > 0.4;
    }

    $q1->shutdown();
    $q2->shutdown();

    eq_or_diff \@order1, [map { "one $_" } 1..5], "all of one looks good";
    eq_or_diff \@order2, [map { "two $_" } 1..5], "all of two looks good";
}

timeout: {
    my $bad = Socialtext::Async::WorkQueue->new(
        name => 'bad',
        cb => sub {
            pass 'work on bad job';
            Coro::AnyEvent::sleep 10;
        }
    );
    $bad->enqueue(['anything']);
    eval {
        $bad->shutdown(1.0);
    };
    like $@, qr/timeout/, "flush timeout";
}

recursive: {
    my $todo = 1;
    my $sync = Coro::rouse_cb;
    my $q; $q = Socialtext::Async::WorkQueue->new(
        name => 'recursive',
        cb => sub {
            my $ok = shift;
            is $ok, 'alright', "recursive call alright";
            if ($todo) {
                $todo = 0;
                pass 'first pass, queue still active';
                ok $q->enqueue(['alright','a job']),
                    "queued a job from within runner";
                is $q->size, 2, "two jobs now";
                eval { $q->shutdown };
                ok $@, 'cannot shutdown queue from runner thread';
                $sync->();
            }
            else {
                my $cluck;
                local $SIG{__WARN__} = sub {
                    $cluck = shift;
                };
                pass 'second pass, queue should already be shut down';
                ok !$q->enqueue(['bad','should not run']),
                    "didn't queue a job";
                like $cluck, qr/attempt to enqueue job.+after shutdown/,
                    "emits warning when enqueueing job after shutdown";
            }
        }
    );
    $q->enqueue(['alright','first job']);
    is $q->size, 1, "enqueued first recursive job";
    Coro::rouse_wait $sync;
    pass 'sync to shut down';
    $q->shutdown();
}

shutdown_chain: {
    my $top_cv = AE::cv;
    $top_cv->begin;
    my $got_after = 0;
    my $chain = Socialtext::Async::WorkQueue->new(
        name => 'chain',
        cb => sub {
            pass 'work on chain job';
        },
        after_shutdown => sub {
            pass 'after shutdown';
            $got_after = 1;
            $top_cv->end;
        }
    );
    $chain->enqueue(['job']);
    $chain->enqueue(['job 2']);
    is $chain->size, 2, "two jobs";
    $chain->shutdown_nowait();
    $top_cv->recv;
    is $got_after, 1, 'chained shutdown';
}

cancel: {
    my $worked_on = 0;
    my $q; $q = Socialtext::Async::WorkQueue->new(
        name => 'for_cancelling',
        cb => sub {
            pass 'work on just one job';
            $worked_on++;
            $q->drop_pending();
            is $q->size, 1, "all jobs except this one cleared";
        }
    );
    $q->enqueue(['job 1']);
    $q->enqueue(['job 2']);
    $q->enqueue(['job 3']);
    is $q->size, 3, "three jobs";
    $q->shutdown();
    is $worked_on, 1, 'worked on exactly one job';
}

pass 'all done';
