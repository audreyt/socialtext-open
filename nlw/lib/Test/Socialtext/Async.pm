package Test::Socialtext::Async;
# @COPYRIGHT@
use 5.12.0;
use warnings;
use AnyEvent;
use AnyEvent::HTTP;
use Test::More;
use Time::HiRes qw/sleep/;
use Socialtext::JSON qw/decode_json/;
use POSIX qw/:sys_wait_h/;

use base 'Exporter';
our @EXPORT = qw(wait_until_pingable empty_port fork_off kill_kill_pid kill_kill_all);

sub wait_until_pingable {
    my $port = shift;
    my $kind = shift || 'proxy';
    my $path = ($kind eq 'nlw-psgi') ? '/data/version' : '/ping';
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $ping_err = '?';
    my $started = AE::now;
    my $content;
    while (AE::now - $started < 30.0) {
        my $cv = AE::cv;
        my $t = AE::timer 5, 0, sub { $ping_err = 'timeout'; $cv->send(0) };
        my $r = http_request 'GET' => "http://localhost:$port$path",
            timeout => 1,
            sub {
                my ($body,$hdr) = @_;
                if ($hdr->{Status} == 200) {
                    undef $ping_err;
                    $content = $body;
                    $cv->send(1);
                }
                else {
                    $ping_err = $hdr->{Reason};
                    $cv->send(0);
                }
            };
        last if $cv->recv;

        undef $t;
        undef $r;
        diag "wait_until_pingable: waiting for $kind...";
        sleep 0.25;
    }
    die "wait_until_pingable: server didn't respond to a ping after 30 seconds"
        if $ping_err;
    pass "wait_until_pingable: $kind has started (".
        (AE::now - $started)." seconds)";

    $content =~ s/^.+?{/{/; # remove unparsable cruft
    given ($kind) {
        when ('nlw-psgi') {
            ok $content, "wait_until_pingable: response says '$content'";
        }

        my $got = decode_json($content);
        when ('proxy') {
            is_deeply $got, {
                "/ping" => { rc => 200, body => "pong", service => 'json-proxy' },
            }, "wait_until_pingable: got correctly formatted response";
        }
        default {
            is $got->{ping}, 'ok', "wait_until_pingable: response says 'ok'";
        }
    }
}

# empty_port is from Test::TCP, *NOT* copyright Socialtext:
sub empty_port {
    my $port = shift || 10000;
    $port = 19000 unless $port =~ /^[0-9]+$/ && $port < 19000;

    require IO::Socket::INET;

    while ( $port++ < 20000 ) {
        local $@;
        my $sock = IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp',
            ReuseAddr => 1,
        );
        if ($sock) {
            return ($port, $sock) if wantarray;
            return $port;
        }
    }
    die "empty_port: no free ports?!";
}

our @forkers;

sub fork_off {
    my @args = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $pid = fork;

    if (!defined $pid) {
        die "fork_off: can't fork $args[0]: $!";
    }
    elsif ($pid) {
        Test::More::pass "fork_off: forked $pid: ".join(' ',@args);
        push @forkers, $pid;
        return $pid;
    }
    else { # child processs
        @forkers = ();
        close STDIN;
        unless ($ENV{ST_DEBUG_ASYNC}) {
            close STDOUT;
            close STDERR;
        }
        exec(@args) or die "fork_off: can't exec: $!";
    }
}

sub kill_kill_pid {
    my $pid = shift;
    my $delay = shift || 5;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    return unless kill(0,$pid);
    Test::More::diag "kill_kill_pid: starting to reap $pid, timeout $delay";
    kill 2, $pid;

    my $start = time;
    my $got;
    my $exit;
    while (1) {
        sleep 0.25;
        my $offset = (time - $start);
        $got = waitpid $pid, WNOHANG;
        if (!defined($got) or $got == -1 or $got == $pid) {
            Test::More::diag "kill_kill_pid: waitpid got $got";
            $exit = $?>>16 if $got == $pid;
            last;
        }

        my $sig = ($offset < $delay) ? 2 : 9;
        Test::More::diag "kill_kill_pid: kill $pid with $sig";
        kill $sig, $pid;
    };

    Test::More::is $exit, 0, "kill_kill_pid: killed $pid";
    return $exit;
}

sub kill_kill_all {
    my $delay = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    for my $pid (@forkers) {
        kill_kill_pid($pid => $delay);
    }
    @forkers = ();
}

END { local $?; kill_kill_all() }

1;
__END__

=head1 NAME

Test::Socialtext::Async - Test utils for async stuff

=head1 SYNOPSIS

  use Test::Socialtext::Async;
  my $port = empty_port();
  fork_off('/path_to_binary', '--port', $port);
  wait_until_pingable($port, 'proxy');
  kill_kill_pid($pid, $delay_between_kills); # kill with SIGINTs then SIGKILL
  kill_kill_all(); # kill all 'fork_off'-ed processes.

=head1 DESCRIPTION

Various testing utilities for async apps.

The C<kill_kill_all> function will be run automatically at END time, but it's
safe to run it before then.

=cut
