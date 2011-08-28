# @COPYRIGHT@
package Socialtext::System;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw/backtick timeout_backtick shell_run quote_args/;

our $SILENT_RUN = 0;
our $TIMEOUT = 0;
our $VMEM_LIMIT = 0;

use IPC::Run qw(run timeout);
use POSIX ();
use BSD::Resource qw(setrlimit get_rlimits);
use namespace::clean;


# like qx()'s, but use the safe, non-shell-interpolated call
sub backtick {
    my $opts = (ref $_[$#_] && ref $_[$#_] eq 'HASH') ? pop(@_) : {};
    $@ = 0;
    $? = 0;
    my $out;
    $out = $opts->{stdout} if $opts->{stdout};
    my $err;
    my $in = $opts->{stdin} || \undef;
    eval {
        # STDIN  needs to be closed explicitly
        my @args = (\@_, '<', $in, '>', ref($out) ? $out : \$out, '2>', \$err);

        # init must happen before timeout:
        push @args, init => \&_vmem_limiter
            if $VMEM_LIMIT;
        push @args, timeout($TIMEOUT, exception => 'Command Timeout')
            if $TIMEOUT;

        # IPC::Run::run returns true on success
        my $return = run(@args);
        die $err unless $return;
    };
    return $out unless $opts->{stdout};
}

{
    my $rlimits = get_rlimits();
    sub _vmem_limiter {
        # limit Virtual Memory and Address Space
        for (qw(RLIMIT_VMEM RLIMIT_AS)) {
            if (exists $rlimits->{$_} and $VMEM_LIMIT > 0) {
                setrlimit($rlimits->{$_}, $VMEM_LIMIT, $VMEM_LIMIT)
            }
        }
    }
}

sub timeout_backtick {
    my $timeout = shift;
    local $TIMEOUT = $timeout;
    return backtick(@_);
}

sub shell_run {
    my @args = @_;
    
    my $no_die = $args[0] =~ s/^-//;
    if (@args == 1) {
        print "$args[0]\n" unless $SILENT_RUN;
    }
    else {
        print quote_args(@args) . "\n" unless $SILENT_RUN;
    }

    my $rc = system(@args);
    return if $no_die or $rc == 0;

    if ($? == -1) {
       die "@args: failed to execute: $!\n";
    }
    elsif ($? & 127) {
       die sprintf "@args: child died with signal %d, %s coredump\n",
           ($? & 127),  ($? & 128) ? 'with' : 'without';
    }
    die sprintf "@args: child exited with value %d\n", $? >> 8;
}

sub quote_args {
    for (@_) {
        if ($_ eq '') {
            $_ = q{""};
        }
        elsif ( m/[^\w\.\-\_]/ ) {
            s/([\\\$\'\"])/\\$1/g;
            $_ = qq{"$_"} if /\s/;
        }
    }
    return join ' ', @_;
}

# this is the POSIX-y way of saying `ulimit -n`
sub open_filehandle_limit {
#     warn "artificial filehandle limit\n";
#     return 30;
    my $fh_threshold = eval {POSIX::sysconf(POSIX::_SC_OPEN_MAX)};
    $fh_threshold = 1024 unless ($fh_threshold && $fh_threshold > 0);
    return $fh_threshold;
}

sub open_filehandles {
    opendir my $dh, "/proc/$$/fd" or return 0;
    my @open = readdir($dh);
    my $num = @open - 2;
    closedir $dh;
    return $num;
}

1;
