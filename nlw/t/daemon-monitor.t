#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::Socialtext tests => 123;
use File::Temp qw/tempfile/;
use Time::HiRes ();
use POSIX ();
use Socialtext::AppConfig;
use Socialtext::Paths;
use Test::Socialtext::Async;

POSIX::setsid;

fixtures(qw( base_layout serial));

ok -x 'bin/st-daemon-monitor', "it's executable";

our $test_dir   = Socialtext::AppConfig->test_dir();
our $log_dir    = Socialtext::Paths->log_directory();
our $touch_file = "$test_dir/mon";
our $init_cmd   = qq{/bin/touch $touch_file};

END {
    local $?; # don't clobber it via system()
    # try to clean things up before we go
    diag "cleanup: killall -9 st-daemon-monitor";
    system("killall -9 st-daemon-monitor");
    diag "cleanup: killall -9 cranky.pl";
    system("killall -9 cranky.pl");
    unlink $touch_file;
}

sub fork_and_exec {
    my @cmd = @_;
    my $pid = fork();
    if ($pid || !defined($pid)) {
        ok $pid, "forked @cmd";
        return $pid;
    }
    exec(@cmd) or die "can't exec: $!";
}

sub reap {
    my $pid = shift;
    for (1..50) {
        return if (waitpid($pid,1) == $pid); # non-blocking
        kill 9, $pid;
        return if (waitpid($pid,1) == $pid); # non-blocking
        #diag("waiting for child process...");
        Time::HiRes::sleep(0.1);
    }
    die "failed to reap $pid";
}

my $last_log;
my ($pid_fh,$pidfile) = tempfile();
close $pid_fh;

sub test_monitor ($$;$) {
    my $cranky = shift;
    my $mon_args = shift;
    my $process_lives = shift || undef;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    unlink $touch_file;
    pass "begin ($cranky; $mon_args)";

    my $cranky_pid = fork_and_exec($cranky);
    open my $fh, '>', $pidfile;
    print $fh $cranky_pid,$/;
    close $fh;

    my $reaped = 0;
    if ($cranky =~ m#^/bin/true#) {
        reap($cranky_pid);
        $reaped = 1;
    }
    elsif ($cranky =~ m#^/bin/false#) {
        reap($cranky_pid);
        unlink $pidfile;
        $reaped = 1;
    }
    else {
        sleep 1;
    }

    system("/bin/bash","-c",":> $log_dir/nlw.log");

    my $rc = system(
        "bin/st-daemon-monitor ".$mon_args.
        qq{ --pidfile $pidfile --init "$init_cmd"}
    );
    my $exit = $rc >> 8;

    if ($process_lives) {
        is $exit, 0, "didn't kill the daemon";
        ok !-f $touch_file, "didn't run the init cmd";
    }
    else {
        is $exit, 1, "killed the daemon";
        ok -f $touch_file, "ran the init cmd";
    }

    if (!$reaped) {
        reap($cranky_pid);
    }
    pass "done ($cranky; $mon_args)";

    $last_log = '';
    eval {
        local $/;
        open my $logfh, '<', "$log_dir/nlw.log";
        ($last_log) = <$logfh>;
        close $logfh;
    };
}

sub logged_like ($) {
    my $re = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    like $last_log, qr/$re/m, 'logged correctly';
}

my $update_procs = `/usr/bin/pgrep -f st-appliance-update`;
is $update_procs, '', "no st-appliance-update is running before the test"
    or die "shut down any st-appliance-update procs/vims before running this test";

my $port = empty_port;
my $c = "dev-bin/cranky.pl --port $port ";

test_monitor('/bin/sleep 5', ''                           => 'lives');
test_monitor('/bin/sleep 5', '--rss 32 --vsz 32 --fds 10' => 'lives');

# special case: harness will reap
test_monitor('/bin/true','');
logged_like qr/is (gone|zombified)/;

# special case: harness will reap, remove pidfile
test_monitor('/bin/false','');
logged_like qr/can't read pidfile/;

test_monitor($c.'--ram 64',         '--rss 64');
logged_like qr/is too big \(RSS\)/i;

test_monitor($c.'--ram 64',         '--vsz 256' => 'lives');
test_monitor($c.'--ram 64',         '--vsz 64');
logged_like qr/is too big \(vsize\)/i;
test_monitor($c.'--ram 64 --fds 64','--vsz 256 --fds 32');
logged_like qr/has too many files open/i;
test_monitor($c.'--fds 64',         '--vsz 256 --fds 32');
logged_like qr/has too many files open/i;

socket_tests: {
    # check for open port only; monitor doesn't try to connect

    test_monitor($c.'--after 5 --serv none', ''            => 'lives');
    test_monitor($c.'--after 5 --serv none', "--tcp $port"           );
    logged_like qr/tcp port $port is not open/i;
    test_monitor($c.'--after 5',             "--tcp $port" => 'lives');

    # cranky should give a 403
    test_monitor(
        $c.'--serv http',
        "--http --tcp $port"
    );
    logged_like qr/non-200/;

    # cranky gives a 200
    test_monitor(
        $c.'--after 5 --serv http --http ok',
        "--http --tcp $port"
        => 'lives'
    );

    test_monitor(
        $c.'--serv stall',
        "--http --tcp $port"
    );
    logged_like qr/timeout/;
}

appliance_conf_tests: {
    skip("Appliance::Config could not be loaded",19)
        unless use_ok "Socialtext::Appliance::Config";

    {
        my $conf = Socialtext::Appliance::Config->new();
        my %new_conf = (
            monitor_proxy_max_rss    => 64,
            monitor_proxy_max_vsz    => 128,
            monitor_proxy_max_fds    => 32,
            monitor_proxy_tcp_port   => $port,
            monitor_proxy_check_scgi => 1,
            monitor_proxy_check_http => 1,
            monitor_proxy_init_cmd   => $init_cmd,
            monitor_proxy_pidfile    => $pidfile,
        );
        while (my ($k,$v) = each %new_conf) {
            $conf->value($k,$v,'force');
        }
        $conf->save();
    }

    test_monitor($c.'--serv http --http ok','--config proxy' => 'lives');

    test_monitor($c.'--serv http --http ok --ram 64','--config proxy');
    logged_like qr/is too big \(RSS\)/i;
    test_monitor($c.'--serv http --http ok --fds 64','--config proxy');
    logged_like qr/too many files/i;

    test_monitor($c.'--serv http --http 403','--config proxy');
    logged_like qr/non-200/;

    test_monitor($c.'--serv stall', '--config proxy');
    logged_like qr/timeout/;

    my $fakepid = fork_and_exec(
        $^X.q{ -e "sleep 5; st-appliance-update"});
    test_monitor('/bin/false', '--config proxy' => 'lives');
    kill 15, $fakepid;
    reap($fakepid);
}

pass "all done";
