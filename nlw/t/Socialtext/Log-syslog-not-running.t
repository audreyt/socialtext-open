#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Socialtext tests => 2;

use Socialtext::Log;

use Readonly;

Readonly my $ENV_VAR     => 'NLW_TEST_SYSLOG';
Readonly my $INIT_SCRIPT => '/etc/init.d/sysklogd';
Readonly my $LOG_FILE    => '/var/log/nlw.log';
Readonly my $MAX_CHECKS  => 10;
Readonly my $MESSAGE1    => 'oneTwoOhMyGod';
Readonly my $MESSAGE2    => 'neverEverEverSmokinCrack';
Readonly my $PID_FILE    => '/var/run/syslogd.pid';
Readonly my $SLEEP_SECS  => 2;

# This test ensures that we don't die if syslog is not running.

SKIP: {
    skip("not fiddling with syslog unless you set $ENV_VAR", 2)
        unless $ENV{$ENV_VAR};
    Test::More::diag("Stopping/starting your syslog daemon.");
    Test::More::diag("Sudo might prompt for your password.");
    syslog_init('stop');
    wait_for_syslog_to_exit();
    eval { Socialtext::Log->new()->error($MESSAGE1) };
    is($@, '', "Socialtext::Log will not die if syslog is not running");
    syslog_init('start');

    # Here we ensure that deferred messages eventually get through, as long as
    # we call Socialtext::Log again.
    my $seen_it = 0;
    no warnings 'redefine';
    local *Sys::Syslog::syslog = sub {
        my ( $priority, $format, @args ) = @_;

        $seen_it++ if (
            $#args == 0
            && $args[0] =~ /\Q$MESSAGE1\E/
            && $priority eq 'ERR'
        );
    };
    Socialtext::Log->new()->emergency($MESSAGE2);
    is( $seen_it, 1, 'Stored messages eventually get through.' );
}

sub syslog_init {
    my ( $command ) = @_;

    my $exit_code = (system 'sudo', $INIT_SCRIPT, $command) >> 8;

    die "$INIT_SCRIPT $command exited nonzero: $exit_code"
        unless $exit_code == 0;
}

sub wait_for_syslog_to_exit {
    my $checks = 0;
    my $pid = `cat /var/run/syslogd.pid`;

    while ($checks < $MAX_CHECKS) {
        kill 0, $pid;
        if ($!{ESRCH}) {
            # The process no longer exists.
            return;
        } elsif ($!{EPERM}) {
            # Can't kill the process, still exists.
            # do nothing
        } else {
            die "confusing error: kill 0, $pid: $!";
        }
        ++$checks;
        sleep $SLEEP_SECS;
    }
}
