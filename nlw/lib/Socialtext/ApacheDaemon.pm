# @COPYRIGHT@
package Socialtext::ApacheDaemon;
use strict;
use warnings;

use Carp;
use Class::Field qw(field);
use File::Basename ();
use Socialtext::AppConfig;
use Socialtext::File;
use Socialtext::System;
use Readonly;
use Time::HiRes qw( sleep time );
use User::pwent;
use IPC::Run ();
use Try::Tiny;

# Set this if you want some debugging output.
our $Verbose = 0;

field 'conf_file';
field 'name';

# These can all be fractional seconds because we're using Time::HiRes.
Readonly my $SLEEP_SECONDS                    => 0.1;
Readonly my $PATIENT_SECONDS_AFTER_FIRST_KILL => 3;
Readonly my $TOTAL_SECONDS_TO_WAIT            => 25;

Readonly my %BINARY => (
    'nginx'       => '/usr/sbin/nginx',
    'apache-perl' => '/opt/perl/5.12.2/bin/apache-perl',
);
Readonly my %ENV_OVERRIDE => (
    'nginx'       => 'NLW_NGINX_PATH',
    'apache-perl' => 'NLW_APACHE_PATH',
);

sub new {
    my $class = shift;

    my $self = bless {@_}, $class;

    unless ( $self->name ) {
        my ($name) = $self->conf_file =~ m{/etc/([^/]+)/}
            or die "Cannot determine apache name from conf_file: ", $self->conf_file;
        $self->name($name);
    }

    return $self;
}

sub conf_filename {
    return $_[0]->name eq 'nginx' ? 'nlw-nginx.conf' : 'nlw-httpd.conf';
}

sub start {
    my $self = shift;

    my $httpd_conf = $self->conf_file;
    -e $httpd_conf or die "$httpd_conf doesn't exist!\n";
    return $self->hup if $self->is_running;
    if ( -f $self->pid_file ) {
        warn "Looks like we have a stale pid file (removing).\n";
        unlink $self->pid_file;
    }
    $self->kill_server_disrespecting_the_pid_file
      if $self->servers_running_on_this_port;
    $self->actually_start;
    $self->wait_for_startup;
}

sub hup {
    my $self = shift;

    $self->output_action('Hupping');
    my $exists = 1;
    $self->send_signal(
        'HUP',
        on_process_doesnt_exist => sub {
            if ( -f $self->pid_file ) {
                unlink $self->pid_file
                    or warn "Couldn't remove " . $self->pid_file . ": $!";
                $exists = 0;
            }
        },
    );
    $self->start unless $exists;
}

sub stop {
    my $self = shift;

    unless ($self->servers_running_on_this_port) {
        warn 'No ', $self->short_binary, " servers to stop.\n";
        return;
    }
    $self->output_action('Stopping');
    $self->try_killing;
    my $start_time = time;
    while ( -f $self->pid_file ) {
        sleep $SLEEP_SECONDS;
        my $elapsed_time = time - $start_time;
        $self->try_killing
            if $elapsed_time > $PATIENT_SECONDS_AFTER_FIRST_KILL;
        die $self->pid_file, " - file still exists after ",
            "$TOTAL_SECONDS_TO_WAIT seconds.  Exiting."
            if $elapsed_time > $TOTAL_SECONDS_TO_WAIT;
    }
    $self->kill_server_disrespecting_the_pid_file
      if $self->servers_running_on_this_port;
}

sub try_killing {
    my $self = shift;

    $self->send_signal(
        'TERM',
        on_process_doesnt_exist => sub {
            if ( -f $self->pid_file ) {
                unlink $self->pid_file
                    or warn "Couldn't remove " . $self->pid_file . ": $!";
            }
        }
    );
}

# Note: this is somewhat of an anachronism, now that we send signal's to
# processes other than the one listed in the pid file.
sub send_signal {
    my $self = shift;

    my $signal = shift;
    my %args   = @_;
    return unless $self->pid;
    my $result = kill $signal, $self->pid;
    $args{on_process_doesnt_exist}->()
        if ! $result and $! =~ /no such (?:file|proc)/i;
    return $result;
}

# this is the sub that makes send_signal's generic name incorrect.
sub kill_server_disrespecting_the_pid_file {
    my $self = shift;

    my @pids = $self->servers_running_on_this_port;
    warn "Killing server(s) [@pids] running with our config, but without a pid file.\n";
    return unless @pids;
    kill 2, @pids
      or die $!;
    $self->wait_for_servers_to_quit
      and return;
    $self->kill_dash_nine_all_has_failed;
}

sub kill_dash_nine_all_has_failed {
    my $self = shift;

    my @pids = $self->servers_running_on_this_port;
    warn "Timed out waiting for pids (@pids) to let go.  kill -9'ing!\n";
    kill 9, @pids
      or warn $!;
    return
      if $self->wait_for_servers_to_quit;
    warn "That didn't even work.  Ryan's code sucks.\n";
}

sub wait_for_servers_to_quit {
    my $self = shift;

    my $x = 0;
    until ($x++ >= (20 / $SLEEP_SECONDS)) {
        sleep $SLEEP_SECONDS;
        return 1 unless $self->servers_running_on_this_port;
    }
    return;
}

sub _suppress_nginx_errlog {
    print STDERR $_[0] unless $_[0] =~
        m#could not open error log file.+/var/log/nginx/error\.log#;
}

sub actually_start {
    my $self = shift;

    my @command = $self->get_start_command;
    $self->ports(); # to check for ports, don't actually need them here

    $self->output_action('Starting');
    try {
        warn "exec: @command\n" if $Verbose;
        my @parm = (\@command, '<', \undef);
        push @parm, '2>', \&_suppress_nginx_errlog if ($self->name eq 'nginx');
        IPC::Run::run(@parm) or die "exited $?\n";
    }
    catch {
        chomp;
        die 'Cannot start ', $self->short_binary, " with @command: $_.\n"
    };
    $self->maybe_test_verbose("\nStarting ", $self->short_binary, " .\n");
}

sub wait_for_startup {
    my $self = shift;

    my $x = 0;
    until ( -f $self->pid_file ) {
        sleep $SLEEP_SECONDS;
        $self->maybe_test_verbose('.');
        if ( $x++ == 120 ) {
            $ENV{NLW_TESTS_DIRTY} = 1;
            die 'Timed out after ' . $x * $SLEEP_SECONDS .  ' seconds while waiting for: '
                . $self->pid_file . "\n"
                . "(Left t/tmp/* intact so you can inspect the aftermath)\n";
        }
    }
    $self->maybe_test_verbose("\n", $self->short_binary, "started\n");
}

sub maybe_warn {
    my $self = shift;

    print STDERR @_ if
        $Verbose
        || (
            ! $ENV{NLWCTL_QUIET}
            && ( $ENV{TEST_VERBOSE} || ! $ENV{HARNESS_ACTIVE} )
        )
}

sub maybe_test_verbose {
    print STDERR @_ if $Verbose || $ENV{NLW_TEST_VERBOSE};
}

sub output_urls {
    my $self     = shift;
    my $hostname = Socialtext::AppConfig->web_hostname();
    my $scheme   = 'http';
    foreach my $port ($self->ports) {
        my $url = "$scheme://$hostname:$port";
        $self->maybe_warn(" URL: $url\n");

        # first port is HTTP, all others thereafter should be HTTPS
        $scheme = 'https';
    }
}

sub output_action {
    my $self = shift;

    my $doing = shift;
    my @ports = $self->ports;
    $self->maybe_warn("$doing ", $self->short_binary, " on ports: @ports\n");
}

sub binary {
    my $self = shift;

    return $self->_binary_override || $self->_binary_default;
}

sub _binary_override {
    my $self = shift;

    my $override = $ENV{$ENV_OVERRIDE{ $self->name }};

    return $override ? $override : '';
}

sub _binary_default {
    my $self = shift;

    return  $BINARY{ $self->name };
}

sub short_binary { return File::Basename::basename( $_[0]->binary ) }

sub get_start_command { 
    my $self = shift;
    my $binary = $self->binary;
    if ($binary =~ m/nginx/) {
        return ($binary, '-c', $self->conf_file);
    }
    return ($binary, '-f', $self->conf_file);
}

sub ports {
    my $self = shift;

    my %ports;
    my $conf_file = $self->conf_file;
    if ($self->name eq 'nginx') {
        $conf_file =~ s/nlw-nginx\.conf$/auto-generated.d\/nlw.conf/;
        %ports =
            map { $_ => 1 }
            grep { defined $_ }
            map { /^\s*listen\s+(?:[\d\.]*:)?(\d+);\s*$/i ? $1 : undef }
            Socialtext::File::get_contents($conf_file);
    }
    else {
        %ports =
            map { $_ => 1 }
            grep { defined $_ }
            map { /^\s*(?:Listen|Port)\s+(?:[\d\.]*:)?(\d+)/i ? $1 : undef }
            Socialtext::File::get_contents($conf_file);
    }
    unless (%ports) {
        die "Could not find any ports in $conf_file";
    }
    return sort keys %ports;
}

sub error_log { return $_[0]->log('ErrorLog'); }

sub access_log { return $_[0]->log('CustomLog'); }

sub log {
    my $self = shift;

    my $which = shift;
    die unless defined $which;
    my $log = Socialtext::File::get_contents( $self->parse_from_config_file($which) );
    # Strip irritating prefix stuff:
    $log =~ s/\[\w+\s+\w+\s+\d+\s+\d{2}:\d{2}:\d{2} \d{4}\] \S+://g;
    return $log;
}

sub blank_log_files {
    my $self = shift;

    for (qw'ErrorLog CustomLog') {
        my $filename = $self->parse_from_config_file($_);
        next unless -f $filename;
        open my $fh, '>', $filename;
    }
}

sub pid {
    my $self = shift;

    return unless -f $self->pid_file;
    eval {
       chomp(my $pid = Socialtext::File::get_contents( $self->pid_file ));
       return $pid;
    };
}

sub pid_file {
    return $_[0]->parse_from_config_file(qr/Pid(?:File)?/i);
}

sub is_running {
    my $self = shift;
    my $pid = $self->pid;

    return 0 unless $pid;
    return -f $self->pid_file and kill 0, $pid;
}

sub servers_running_on_this_port {
    my $self = shift;

    my %ports = map { $_=>1 } $self->ports;
    my $shortbin = $self->short_binary;

    # netstat -t tcp, -l listen ports, -p gives PID, -n doesn't resolve names
    # e.g.:
    # tcp  0  0  0.0.0.0:22001    0.0.0.0:*  LISTEN  3762/nlw-nginx.conf
    # tcp  0  0  127.0.0.1:23001  0.0.0.0:*  LISTEN  3736/apache-perl
    # tcp  0  0  127.0.0.1:24001  0.0.0.0:*  LISTEN  3736/apache-perl
    # tcp  0  0  0.0.0.0:21001    0.0.0.0:*  LISTEN  3762/nlw-nginx.conf
    my @netstat = split "\n", backtick(qw(netstat -tnlp));
    my @pids = 
        map { $_->{pid} }
        grep { $ports{$_->{port}} }
        #grep { $_->{proc} =~ /\Q$shortbin\E/ }
        map {
            my @f = split(/\s+/,$_);
            my ($port) = ($f[3] =~ /^.+:(\d+)$/);
            my ($pid,$proc) = split('/',$f[6]||'');
            my $x = +{port => $port, pid => $pid||'?', proc => $proc||'?'};
#              use Data::Dumper; warn Dumper($x),$/;
            $x;
        }
        grep /^tcp/, @netstat; # ensure parsable lines

    warn "found $shortbin PIDs: ".join(', ',@pids)."\n" if @pids;
    return @pids;
}

sub parse_from_config_file {
    my $self = shift;
    my $looking_for = shift;
    my $conf_file = $self->conf_file;

    if ($looking_for =~ m/pid/i) {
        $conf_file =~ s#auto-generated\.d/nlw\.conf#nlw-nginx.conf#;
    }
    Socialtext::File::get_contents( $conf_file ) =~ /^$looking_for\s*(\S+)/m
        or return '';
    #    or die "Couldn't find $looking_for in " . $conf_file;
    my $pid_file = $1;
    $pid_file =~ s/;$//;
    return $pid_file;
}

1;

