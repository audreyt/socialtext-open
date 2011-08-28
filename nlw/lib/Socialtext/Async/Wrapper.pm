package Socialtext::Async::Wrapper;
# @COPYRIGHT@
use warnings;
use strict;
use Moose::Exporter ();
use Coro;
use Coro::State ();
use Coro::AnyEvent;
use Guard;
use AnyEvent::Worker;
use Carp qw/carp croak cluck confess/;
use Scalar::Util qw/blessed/;
use Try::Tiny;
use BSD::Resource qw/setrlimit get_rlimits/;

use Socialtext::TimestampedWarnings;
use Socialtext::Timer qw/time_scope/;
use Socialtext::Log qw/st_log/;
use Socialtext::SQL qw/with_local_dbh/;
use Socialtext::Moose::Util;

use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Async::Wrapper - wrap code to run in a worker process.

=head1 SYNOPSIS

    use Moose;
    use Socialtext::Async::Wrapper;

    worker_function do_x => sub {
        my $input = shift;
        # ... runs in worker
        return alright => 'i was passed: '.$input;
    };
    my @result = do_x("something");

    worker_wrap replacement => 'Some::Slow::class_method';
    sub replacement {
        my $class = shift; # e.g. 'Some::Slow'
        # executes the original method in the worker:
        my $result = call_orig_in_worker(replacement => $class, @_);
    }
    # ... then elsewhere
    my $r = Some::Slow->class_method(param_a => 1, param_b => 2);

=head1 DESCRIPTION

Currently this library is Moose-y sugar around C<AnyEvent::Worker>.

Running "blocking" or "slow" code in a worker has two key advantages: it uses
another CPU core for speed and it doesn't block your evented daemon from doing
I/O tasks (like accepting new clients, receiving requests, sending responses).

The first call to a wrapped bit of code will launch the sub-process.

Calling a wrapped method will transmit arguments to the subprocess and receive
results (to the extent that C<Storable> and C<AnyEvent::Worker> can do so).  A
string exception will be thrown starting with "Worker shutdown: " if a
communication or other fatal error occurs.  Other exceptions are
passed-through as-is.

To affect startup and shutdown of the worker process, overload the
Socialtext::Async::Wrapper::Worker::BUILD and DEMOLISH methods.

To affect what happens before each request (e.g. cache clearing), override
Socialtext::Async::Wrapper::Worker::before_each.  before_each B<MUST NOT>
throw an exception.

=cut

Moose::Exporter->setup_import_methods(
    compat_with_meta(qw(worker_wrap worker_function)),
    as_is => [qw(worker_make_immutable call_orig_in_worker ping_worker)],
);

our $IN_WORKER = 0;
our @AT_FORK;
our $VMEM_LIMIT = 512 * 2**20; # MiB
our $REPORT_EVERY = 3600; # seconds

=head1 CLASS METHODS

=over 4

=item C<< RegisterCoros() >>

Marks currently active Coros for non-deletion.  At fork, other Coros will be
cancelled.

=cut

sub RegisterCoros {
    # mark the current coros so we don't kill them in the sub-process.
    for my $coro (Coro::State::list()) {
         $coro->{_preserve_on_fork} = 1;
    }
}

=item C<< RegisterAtFork(sub { ... }) >>

Register some code to run after forking.  Will run after extraneous coros have
been cancelled but before any "standard" initializations the socialtext stack
needs.

=cut

sub RegisterAtFork {
    my $class = shift;
    push @AT_FORK, shift;
}

sub _InWorker {
    my $class = shift;
    my $name = shift;

    # Prevents recursive workers:
    $IN_WORKER = 1;

    # notify EV that we've forked
    eval { EV::default_loop()->loop_fork; };
    warn $@ if $@;

    no warnings 'redefine';
    Socialtext::TimestampedWarnings->import;

    for my $coro (Coro::State::list()) {
        unless (
            $coro == $Coro::current ||
            $coro->{desc} =~ /^\[/ ||
            $coro->{_preserve_on_fork}
        ) {
            $coro->cancel;
        }
    }

    for my $fork_cb (@AT_FORK) {
        eval { $fork_cb->() };
    }

    # AnyEvent::Worker ignores SIGINT, un-ignore it so st-daemon-monitor
    # can kill us.
    $SIG{INT} = 'DEFAULT';

    # make it reconnect
    Socialtext::SQL::disconnect_dbh();

    # clear caches.
    Socialtext::Cache->clear();
    # but make sure it uses the user-cache until we clear it.
    $Socialtext::User::Cache::Enabled = 1;

    # st_log is disconnected by AnyEvent::Worker right after fork.
    # Reconnect it here.
    Sys::Syslog::closelog();
    Socialtext::Log->_renew();

    # If something's messed up with Coro/Ev/AnyEvent this will fail:
    my $cv = AE::cv;
    my $t = AE::timer 0.000001, 0, sub {
        $cv->send("seems to be working");
    };
    my $ok = eval { $cv->recv };
    $ok ||= 'is broken';
    st_log()->info("$name async worker, AnyEvent $ok");

    my $lim = $VMEM_LIMIT;
    if ($lim) {
        my $rlimits = get_rlimits();
        # limit Virtual Memory and Address Space
        for my $res (qw(RLIMIT_VMEM RLIMIT_AS)) {
            next unless exists $rlimits->{$res};
            setrlimit($rlimits->{$res}, $lim, $lim);
        }
    }
}

=back

=cut

{
    package Socialtext::Async::Wrapper::Worker;
    use Moose;
    use Data::Dumper;
    use Try::Tiny;
    use Guard;
    use Socialtext::Log qw/st_log st_timed_log/;
    use namespace::clean -except => 'meta';

    has 'last_report' => (is => 'rw', isa => 'Num', default => \&AE::time);
    has 'name' => (is => 'rw', isa => 'Str');

    # When do we consider worker requests having taken "too long" and should
    # log them? (in seconds)
    our $TOO_LONG = 1.0;

    sub BUILD {
        my $self = shift;
        # This BUILD runs in the child worker process only.
        Socialtext::Async::Wrapper->_InWorker($self->name);
        return;
    }

    sub DEMOLISH {
        my $self = shift;
        st_log()->info($self->name." async worker stopping");
    }

    sub report {
        my $self = shift;
        my $rpt = Socialtext::Timer->ExtendedReport();
        delete $rpt->{overall};
        Socialtext::Timer->Reset();
        st_timed_log('info',uc($self->name),'TIMERS',0,{},undef,$rpt);
    }

    sub before_each {
        my ($self, $timer, $argref) = @_;
        try {
            # most of these copied from Socialtext::Handler::Cleanup
            Socialtext::Cache->clear();
            Socialtext::SQL::invalidate_dbh();
            File::Temp::cleanup();
        }
        catch {
            warn "in before_each: $_";
        };

        Socialtext::Timer->Continue($timer);
        my $t_st = AE::time;
        my $guard = guard {
            Socialtext::Timer->Pause($timer);
            my $t_diff = AE::time - $t_st;
            if ($t_diff > $TOO_LONG) {
                st_log->info("long running worker '$timer' - $t_diff");
                local $Data::Dumper::Indent=0;
                warn Dumper({"long running worker '$timer'" => $argref}) . "\n";
            }
        };

        return $guard;
    }

    sub worker_ping {
        my $self = shift;
        $self->before_each('worker_ping');
        Socialtext::SQL::get_dbh();
        $Socialtext::Log::Instance->debug("async worker is OK");
        my $now = AE::time;
        if ($now - $self->last_report >=
            $Socialtext::Async::Wrapper::REPORT_EVERY)
        {
            $self->last_report($now);
            $self->report;
        }
        return {'PING'=>'PONG'}
    }

    # other methods get installed here by worker_wrap and worker_function.
}

=head1 EXPORTS

=over 4

=cut

=item worker_wrap replacement => 'Slow::Class::method';

Wrap some slow class-method so that it runs in a worker child process.  All
calls to that method are proxied to the worker.

The replacement should be a function in the current package.  It should call
C<call_orig_in_worker> after perhaps doing some parent-process caching.

=cut

sub worker_wrap {
    my $caller_or_meta = shift;
    my $replacement = shift;
    my $method_to_wrap = shift;
    my %args = @_;

    no warnings 'redefine';
    no strict 'refs';

    my $meta = compat_meta_arg($caller_or_meta);

    (my $orig_pkg = $method_to_wrap) =~ s/::.+?$//;
    my $orig_method = \&{$method_to_wrap};
    my $worker_name = "worker_$replacement";
    my $replacement_method = $meta->find_method_by_name($replacement)->body;

    # Install a method to call the original, "real" method.  This
    # worker_method will be called in the AnyEvent::Worker sub-process.
    my $worker_method = Moose::Meta::Method->wrap(
        name => $worker_name,
        package_name => 'Socialtext::Async::Wrapper::Worker',
        body => sub {
            my $self = shift;
            my $guard = $self->before_each($worker_name => \@_);
            my $class_or_obj = shift;
            return $class_or_obj->$orig_method(@_);
        },
    );
    Socialtext::Async::Wrapper::Worker->meta->add_method(
        $worker_name => $worker_method);

    # Swap in a replacement for the original method.  This replacement *must*
    # call the call_orig_in_worker() function.
    *{$method_to_wrap} = sub {
        # prevent recursive calls into additional workers
        if ($IN_WORKER) { goto $orig_method; }
        else { goto $replacement_method; }
    };
}

=item worker_function func_name => sub { ... }

Installs C<sub func_name { ... }> into the current package.  The supplied sub
will actually run in the worker process.

=cut

sub worker_function {
    my $caller_or_meta = shift;
    my $name = shift;
    my $code = shift;

    my $meta = compat_meta_arg($caller_or_meta);

    my $worker_name = "worker_$name";
    my $worker_method = Moose::Meta::Method->wrap(
        name => $worker_name,
        package_name => 'Socialtext::Async::Wrapper::Worker',
        body => sub {
            my $self = shift; # instance of Socialtext::Async::Wrapper::Worker
            my $guard = $self->before_each($worker_name => \@_);
            shift; # undef
            return $code->(@_);
        },
    );
    Socialtext::Async::Wrapper::Worker->meta->add_method(
        $worker_name => $worker_method);

    my $method = Moose::Meta::Method->wrap(
        name => $name,
        package_name => $meta->name,
        body => sub {
            return call_orig_in_worker($name, undef, @_);
        },
    );

    $meta->add_method($name => $method);
    return;
}

=item worker_make_immutable

Make the Socialtext::Async::Wrapper::Worker package immutable (optimize the
worker for speed).  Call this after you've installed all the wrapped
methods/functions you need.

=cut

our $ae_worker;

sub worker_make_immutable {
    my $name = shift;
    confess "can't make worker immutable in the worker process" if $IN_WORKER;
    Socialtext::Async::Wrapper::Worker->meta->make_immutable(
        inline_constructor => 1);
    _setup_ae_worker($name) unless $ae_worker;
}

sub _setup_ae_worker {
    my $name = shift;

    $name ||= try { $Socialtext::WebDaemon::SINGLETON->Name() };
    cluck "no name!" unless $name;
    $name ||= 'async-worker';

    confess "can't start worker in the worker process" if $IN_WORKER;
    confess 'IO::AIO shouldnt be loaded' if $INC{'IO/AIO.pm'};

    st_log()->info("$name async worker starting...");

    my %parent_args = (
        on_error => sub {
            my ($w,$error,$fatal) = @_;
            warn(($fatal ? "fatal " : "") ."ae-worker error: $error\n");
            delete $ae_worker->{on_error}; # remove circular ref
            undef $ae_worker;
        },
        timeout => 30,
    );
    my %child_args = (
        class => 'Socialtext::Async::Wrapper::Worker',
        args => [{name => $name}],
    );

    # get out of the event handler thread:
    my $coro = async {
        $Coro::current->{desc} = "AnyEvent::Worker";
        with_local_dbh {
            $ae_worker = AnyEvent::Worker->new(\%child_args, %parent_args);
        };
    };
    $coro->cede_to;
    $coro->join;
    st_log()->info("$name async worker started");
}

=item call_orig_in_worker name => $class[, @params]

Calls the 'name' method installed by C<worker_wrap>, passing in optional
parameters.

=cut

# Used by the replacement method (executing in the parent) to invoke the
# "real" method in the Worker process.
sub call_orig_in_worker {
    my $replacement = shift;
    my $tgt_class = shift;
    $tgt_class = ref($tgt_class) if blessed $tgt_class;
    my $worker_method_name = "worker_$replacement";

    confess "Cannot call_orig_in_worker from within a worker"
        if $IN_WORKER;

    _setup_ae_worker() unless $ae_worker;

    my $cv = AE::cv;
    $ae_worker->do($worker_method_name => $tgt_class, @_, sub {
        my $wrkr = shift; # AnyEvent::Worker, but never a ::Pool
        if (my $e = $@) {
            if (!$wrkr->{fh}) {
                # fh is deleted for fatal errors
                $cv->croak("Worker shutdown: $e");
            }
            else {
                $cv->croak("Worker died: $e")
            }
        }
        else {
            $cv->send(\@_);
        }
    });
    # TODO pause all Socialtext::Timer while sleeping in coro
    my $result = $cv->recv; # may croak

    return unless ($result and defined wantarray);
    return wantarray ? @$result : $result->[0];
}

=item ping_worker

Calls the 'ping' method on the worker, dies if worker is unreachable or if the
result was corrupted somehow.

=cut

sub ping_worker {
    my $result = call_orig_in_worker('ping', undef);
    confess "corrupted result" unless $result->{PING} eq 'PONG';
    return $result;
}

1;
__END__

=back

=head1 COPYRIGHT

(C) 2010 Socialtext Inc.
