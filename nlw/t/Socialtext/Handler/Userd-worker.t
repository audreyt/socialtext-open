#!perl
# @COPYRIGHT@
use warnings;
use strict;

# Test that after we kill the worker that clients eventually recover.  The
# test may occasionally fail due to the randomized nature of the test (but
# *always* failed before the fix was made).

use constant CLIENTS => 10;
use Guard;
use AnyEvent;

use Test::Socialtext tests => 11 + 2*CLIENTS;
use Test::Socialtext::Cookie;
use Test::Socialtext::Async;
use Socialtext::JSON qw/decode_json/;
use Socialtext::CredentialsExtractor::Client::Async;
use Proc::ProcessTable ();

BEGIN {
#     $ENV{ST_DEBUG_ASYNC} = 1;
#     $ENV{NLW_DEBUG_SCREEN} = 1;
    POSIX::setsid();
}

fixtures(qw( db ));

my $user = create_test_user();
ok $user, 'created test user';

my $port = empty_port();
my $st_userd = "$ENV{ST_CURRENT}/nlw/bin/st-userd";
die "userd script is not executable" unless -x $st_userd;
diag "starting st-userd on port $port with script $st_userd";

my $pid = fork_off($st_userd,
    '--port' => $port, '--shutdown-delay' => 10, '--http-read-timeout' => 2);
wait_until_pingable($port, 'userd');

my $cv = AE::cv;
my $stopping = 0;

# create this after userd forks:
my $cookie  = Test::Socialtext::Cookie->BuildCookie(user_id => $user->user_id);
my $env = { HTTP_COOKIE => $cookie };

for my $n (1 .. CLIENTS) {
    $cv->begin;
    my $g = guard { $cv->end };
    my $errors = 0;
    my $recovered = 0;
    my $client = Socialtext::CredentialsExtractor::Client::Async->new(
        userd_port => $port,
        cache_enabled => 0,
        timeout => 3,
    );
    my $cb; $cb = sub {
        if ($stopping) {
            undef $g; undef $cb;
            # (error and recovered) or (!error and !recovered):
            is !!$errors, !!$recovered, "client $n - done";
            return;
        }

        my $result = shift;
        if (my $e = $result->{error}) {
            $errors++;
            diag $e;
        }
        elsif ($errors && !$recovered) {
            $recovered++;
        }

        $client->extract_credentials($env,$cb);
    };
    pass "starting client $n";
    $client->extract_credentials($env,$cb);
}

# test is complete when st-userd exits:
$cv->begin;
my $waiter = AE::child $pid, sub {
    my ($child_pid, $status) = @_;
    scope_guard {$cv->end};
    is $status, 9, "st-userd $pid exited with self-inflicted kill -9";
    undef $pid;
};

sub kill_the_worker {
    my $procs = new Proc::ProcessTable('cache_ttys' => 1);
    my @kids = map { $_->pid } grep { $_->ppid == $pid } @{$procs->table};
    for my $kid_pid (@kids) {
        kill 9, $kid_pid;
        pass "killed kid $kid_pid";
    }
}

# open a do-nothing connection that "stalls"
$cv->begin;
my $sleepy; $sleepy = AnyEvent::Handle->new(
    connect => ['127.0.0.1',$port],
    on_connect => sub {
        my $h = shift;
        pass "sleepy connected";
    },
    on_read => sub { $sleepy->destroy; },
    on_eof => sub { $sleepy->destroy; },
    on_error => sub { $sleepy->destroy; },
);
$sleepy->{_foo} = guard { pass "sleepy done"; $cv->end };
$sleepy->push_write("POST /stuserd HTTP/1.0\r\n");
$sleepy->on_drain(sub {
    pass "buffer is flushed";
    kill_the_worker();
    $cv->begin;
    my $death; $death = AE::timer 5, 0, sub {
        pass 'stopping';
        $cv->end;
        $stopping = 1;
        kill 3, $pid;
        undef $death;
    };
});


$cv->recv;

# TODO: check the log to confirm that st-userd shut down gracefully
# (i've just been reading the test output b/c i can't remember the lib that does
# "log_like")

kill_kill_all();
pass "done done";


