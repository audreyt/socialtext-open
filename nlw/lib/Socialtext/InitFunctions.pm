package Socialtext::InitFunctions;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Exporter';

use Carp 'croak';
use POSIX qw(setgid setuid);
use File::Spec ();

our @EXPORT_OK = qw(
    fork_and_exec_daemon_as_user succeed fail system_or_die try_kill
    timeout_waitpid restart assert_absolute_paths );

sub succeed(@) { print @_, "\n"; exit 0; }
sub fail(@)    { print @_, "\n"; exit 1; }

# Try to execute the given system call, and die if it exits nonzero or fails
# to start.
sub system_or_die {
    system(@_);
    if ( $? == -1 ) {
        croak("system @_: $!");
    }
    elsif ( my $code = ( $? >> 8 ) ) {
        croak("@_: exit $code");
    }
}

# Attempt to send the given signal to the given pid.  If the pid doesn't
# exist, return false.  If it fails for any other reason, die.  Otherwise
# return true.
sub try_kill {
    my ( $signal, $pid ) = @_;

    if ( kill $signal, $pid ) {
        return 1;
    }
    elsif ( $!{ESRCH} ) {
        return 0;
    }
    else {
        croak("kill $pid: $!");
    }
}

# Wait for the given pid to exit, but no more than the allotted number of
# seconds.  Return true if the pid exited before the timeout (even if because
# it didn't actually exist), false otherwise.
sub timeout_waitpid {
    my ( $pid, $timeout ) = @_;
    my $expired = 0;

    local $SIG{ALRM} = sub { $expired = 1 };
    alarm $timeout;

    my $reaped = waitpid $pid, 0;

    return !$expired;
}

=head2 fork_and_exec_daemon_as_user( $user, @command )

Fork, then set real and effective UID and GID, and groups list to the
minimal set for $USER and exec the given daemon program.  This is expected
to be a program which itself forks and runs the daemon in the background.
When it exits, the parent process returns the exit code.  If anything
goes wrong, it dies from the perspective of the caller.

=cut

sub fork_and_exec_daemon_as_user {
    my ( $user, @command ) = @_;
    my $pid = fork;
    my ( $uid, $gid ) = ( getpwnam $user )[ 2, 3 ]
        or croak("getwpnam $user: $!");

    if ( !defined $pid ) {
        croak("fork: $!");
    }
    elsif ( $pid == 0 ) {
        local $!;

        # Start the daemon, first setting our real and effective UID and GID,
        # and also our groups list.

        $) = "$gid $gid";
        croak("setegid/setgroups $gid: $!") if $!;
        setgid($gid) or croak("setgid $gid: $!");
        setuid($uid) or croak("setuid $uid: $!");

        exec @command or croak("exec @command $!");
    }
    else {
        my $reaped = wait;
        croak("Confusing result '$reaped' returned from wait()")
            unless $reaped == $pid;
        return ($? >> 8);
    }
}

sub restart {
    system_or_die( $0, 'stop' );
    exec $0, 'start' or croak("exec $0: $!");
}

sub assert_absolute_paths {
    my %checks = @_;

    my $ok = 1;
    for my $key ( sort keys %checks ) {
        if ( not File::Spec->file_name_is_absolute( $checks{$key} ) ) {
            warn qq{Path to $key must be absolute but is "$checks{$key}"\n};
            $ok = 0;
        }
    }
    exit 1 unless $ok;
}

1;
