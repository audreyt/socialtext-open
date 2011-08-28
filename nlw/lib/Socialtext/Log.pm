# @COPYRIGHT@
package Socialtext::Log;
use strict;
use warnings;

use base 'Exporter';
use Log::Dispatch;
use Log::Dispatch::Syslog;
use Socialtext::AppConfig;
use Socialtext::JSON qw/encode_json/;
use Class::Field qw(field);
use Encode;

=head1 NAME

Socialtext::Log - A logging utility class for NLW that dispatches to syslog

=head1 SYNOPSIS

    # log a debugging message via the hub
    $hub->log->debug('hello, this is a debug message');

    # log a notice using the class
    Socialtext::Log->new()->notice('you will be evicted soon'):

=head1 DESCRIPTION

Logging is a critical piece of any application. Socialtext::Log provides a 
very simple tool to enable logging to syslogd(8). Multiple levels
of logging are supported, see syslog(3). Log messages are sent to 
facility local7. See L</CONFIGURATION>.

Methods for each level of logging are automatically created.

=head1 CONFIGURATION

syslogd(8) must be configured to enable logging support. Add something
like the following to /etc/syslog,conf (or equivalent).

    local7.*                        /var/log/nlw.log

syslogd(8) will need to told to reread it's configuration. See the 
man page for details.

=cut

our @EXPORT_OK = qw( st_log st_timed_log );

sub class_id { 'log' }

field log      => -init => 'Log::Dispatch->new';

BEGIN {
    my @deferred_calls;

    # Set up pass-thru functions to parent class
    for my $l (qw( debug info notice warning error critical alert emergency )) {
        no strict 'refs';
        *{$l} = sub {
            local $@;
            local $SIG{PIPE} = sub { die "Syslog SIGPIPE" };
            eval {
                my $self = shift;
                foreach my $call (@deferred_calls) {
                    my $level   = $call->{level};
                    my $message = $call->{message};

                    $self->log->$level(@$message);
                }
                @deferred_calls = ();
                $self->log->$l(@_);
            };

            # Save it for later if we can't connect to syslog.
            if ($@) {
                die unless $@ =~ /no connection to syslog available/;
                push @deferred_calls, {
                    level   => $l,
                    message => [@_]
                };
            }
        };
    }
}

our $Instance;

sub st_timed_log {
    my $method = shift;
    my $command = shift;
    my $name = shift;
    my $user = shift;
    my $data = shift || {};
    my $times = shift;
    my $extended_times = shift;

    my $time;
    if ($times) {
        $time = join(',', map { $_.':'.$times->{$_} } 
                             sort { $times->{$b} <=> $times->{$a} } 
                             keys %$times);
    }
    elsif ($extended_times) {
        my $t = $extended_times;
        $time = join(',', map { "$_($t->{$_}{count}):$t->{$_}{duration}" } 
                             sort { $t->{$b}{duration} <=> $t->{$a}{duration} } 
                             keys %$t);
    }

    $data->{timers} = $time if $time;

    my $user_id = $user
        ? (ref($user) ? $user->user_id : $user)
        : 0;
    my $message = join(',',
        uc($command),
        uc($name),
        "ACTOR_ID:$user_id",
        encode_json($data),
    );

    return st_log($method, $message);
}

=head1 IMPORTABLE SUBROUTINE

=head2 st_log(LEVEL, MESSAGE, [MESSAGE ...])

=head2 st_log->LEVEL(MESSAGE, [MESSAGE ...])

Provides an alternate, convenient method of calling a logging routine without
having to keep track of a C<Socialtext::Log> instance yourself.

For example,

    use Socialtext::Log 'st_log';

    st_log->debug("Riunite on ice...");
    st_log(notice => "so nice!");

=cut

sub st_log {
    my $method = shift;

    __PACKAGE__->new;
    return $method
        ? $Instance->$method(@_)
        : $Instance;
}

=head1 METHODS

=head2 new()

Create or make use of an existing Socialtext::Log object. The class maintains
a singleton instance of the object.

=cut
sub new {
    my $class = shift;
    return $Instance ? $Instance : $class->_renew();
}

sub _renew {
    my $class = shift;
    my $self = bless {}, $class;
    local $@;
    eval {
        $self->_syslog_output;
        $self->_screen_output if $ENV{NLW_DEBUG_SCREEN};
        $self->_devenv_output
            if Socialtext::AppConfig->startup_user_is_human_user();
    };
    warn $@ if $@;

    $Instance = $self;
    return $Instance;
}

=head2 debug_method_call()

Write to the log that a particular method was called.

=cut

sub debug_method_call {
    my $self = shift;
    my ($meth) = ( caller(1) )[3];
    $self->debug("$meth\n");
}


# REVIEW: A signal handler for changing min_level would be nice.
sub _syslog_output {
    my $self = shift;
    $self->log->add(
        Log::Dispatch::Syslog->new(
            name      => 'syslog',
            min_level => Socialtext::AppConfig->syslog_level,
            ident     => 'nlw',
            logopt    => 'pid',
            facility  => 'local7',
            callbacks => [ \&_add_apache_uid ],
        )
    );
}

sub _screen_output {
    my $self = shift;

    require Log::Dispatch::Screen;
    $self->log->add(
        Log::Dispatch::Screen->new(
            name      => 'screen',
            min_level => 'debug',
            callbacks => [ \&_add_newline, \&_add_hash_for_tests ],
        )
    );
}

sub _devenv_output {
    my $self = shift;

    require Socialtext::Paths;
    my $logpath = Socialtext::Paths->log_directory();

    require Log::Dispatch::File::Socialtext;
    $self->log->add(
        Log::Dispatch::File::Socialtext->new(
            name        => 'devenv',
            min_level   => 'debug',
            mode        => 'append',
            filename    => "$logpath/nlw.log",
            close_after_write => 1,
            callbacks   => [ \&_remove_embedded_newlines, \&_add_apache_uid, \&_add_fake_syslog_prefix, \&_add_newline ],
        ) 
    );
}

sub _add_fake_syslog_prefix {
    my %p = @_;
    require POSIX;
    my $now = POSIX::strftime('%b %d %H:%M:%S', localtime());
    return "$now socialtext nlw[$$]: $p{message}";
}

sub _add_apache_uid {
    my %p = @_;

    # We need to pass raw bytes to Sys::Syslog or it dies.
    my $bytes = Encode::encode_utf8($p{message});
    return "[$<] " . $bytes;
}

sub _add_newline {
    my %p = @_;

    $p{message} =~ s/\n*$/\n/;

    return $p{message}
}

sub _add_hash_for_tests {
    my %p = @_;

    $p{message} =~ s/^/# /gm
        if $ENV{HARNESS_ACTIVE};

    return $p{message};
}

sub _remove_embedded_newlines {
    my %p = @_;
    $p{message} =~ s/\n/ /g;
    return $p{message};
}

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

