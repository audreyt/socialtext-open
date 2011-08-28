package Socialtext::Async::WorkQueue;
# @COPYRIGHT@
use Moose;
use MooseX::StrictConstructor;
use MooseX::AttributeHelpers;
use Coro;
use AnyEvent;
use Coro::AnyEvent;
use Coro::Channel;
use Guard;
use Carp qw/croak cluck/;
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Async::WorkQueue

=head1 SYNOPSIS

    use Socialtext::Async::WorkQueue;
    my $q = Socialtext::Async::WorkQueue->new(
        name => 'dispatch',
        cb => {
            my ($arg1, $arg2) = @_;
        }
    );
    $q->enqueue(['one','two']);
    $q->shutdown();

=head1 DESCRIPTION

An infinite length work queue.

Enqueued tasks are worked on in a C<Coro> thread (one thread per work queue),
cede-ing after each job completes.

=head1 CONSTRUCTOR

=over 4

=item cb

A CodeRef to run for each job.

=item name

The name of this queue (defaults to 'work').

=item after_shutdown

An optional CodeRef to call once all pending jobs have been processed after
the queue has been shut down.  Handy for chaining condvars during a
non-blocking shutdown:

    my $cv = AE::cv;
    my $q = Socialtext::Async::WorkQueue->new(
        ...
        after_shutdown => sub {
            my $q = shift;
            $cv->end;
        }
    );
    $cv->begin;
    ...
    $q->shutdown_nowait();
    $cv->recv;

=item prio

Set the Coro thread priority. Either C<< use Coro qw/:prio/; >> or see
L<Coro>.

Defaults to C<Coro::PRIO_NORMAL>.

=back

=cut

has 'cb' => (is => 'ro', isa => 'CodeRef', required => 1);
has 'name' => (is => 'ro', isa => 'Str', required => 1, default => 'work');

has 'after_shutdown' => (
    is => 'ro', isa => 'CodeRef',
    clearer => 'clear_after_shutdown'
);

has 'prio' => (is => 'ro', isa => 'Int', default => Coro::PRIO_NORMAL());

=head2 ATTRIBUTES

=over 4

=item is_working

Is something being worked on right now?

=item is_shutdown

Is the queue shut-down (and will new jobs be rejected)?

=back

=cut

has 'is_working' => (
    is => 'rw', isa => 'Int',
    default => 0,
    writer => '_working',
    init_arg => undef,
);

has 'is_shutdown' => (
    is => 'rw', isa => 'Bool',
    default => undef,
    writer => '_shutdown',
    init_arg => undef,
);


# below attributes are "protected"

has '_runner' => (is => 'rw', isa => 'Coro', predicate => 'has_runner');
has '_cv' => (is => 'rw', isa => 'AnyEvent::CondVar');
has '_chan' => (
    is => 'ro', isa => 'Coro::Channel',
    default => sub {Coro::Channel->new},
);

sub BUILD {
    my $self = shift;
    my $cv;
    if (my $cb = $self->after_shutdown) {
        $cv = AnyEvent->condvar(cb => $cb);
        $self->clear_after_shutdown;
    }
    else {
        $cv = AE::cv();
    }
    $self->_cv($cv);
    $self->_cv->begin; # match in shutdown
}

=head1 METHODS

=over 4

=item enqueue(['arg 1', 'arg 2'])

Enqueue a job, which must be an array-ref.  The contents of the array-ref are
passed in to the C<cb> registered during construction via C<@_>.

=cut

sub enqueue {
    my $self = shift;
    my $job = shift;

    if ($self->is_shutdown) {
        cluck "attempt to enqueue job to ".$self->name." queue after shutdown";
        return;
    }

    croak "can only enqueue array refs" unless ref($job) eq 'ARRAY';
    $self->_chan->put($job);

    # start a runner since this is the first job
    $self->_start unless $self->has_runner;

    return 1;
}

=item size

Returns the size of the queue in number of jobs. The job count increases when
a job is enqueued and decreases B<after> it is worked on.

=cut

sub size {
    my $self = shift;
    return $self->_chan->size + $self->is_working;
}

=item drop_pending()

Drop the reference to all pending jobs.  If a job is currently in progress it
will B<NOT> be cancelled.

=cut

sub drop_pending {
    my $self = shift;
    $self->_reset_chan;
}

sub _reset_chan {
    my $self = shift;
    $self->_chan->[Coro::Channel::DATA()] = [];
}

sub _start {
    my $self = shift;
    $self->_cv->begin;
    $self->_runner(async {
        $Coro::current->{desc} = $self->name." queue runner";
        $Coro::current->prio($self->prio);
        scope_guard { 
            $self->_working(0);
            $self->_cv->end;
        };

        $self->_working(0);
        my $cb = $self->cb;
        while (my $job = $self->_chan->get) {
            $self->_working(1);
            eval { $cb->(@$job) };
            warn "Error processing queue ".$self->name.": $@" if $@;
            undef $@;

            $self->_working(0);
            if ($self->_chan->size) {
                cede;
            }
            else {
                # reset to immediately reclaim AV memory
                $self->_reset_chan;
            }
        }
    });
}

=item shutdown()

=item shutdown(5.0)

Block the current thread and Wait for all jobs to complete.  Prevents new jobs
from being enqueued.

The optional argument is a timeout to wait for jobs to complete, in seconds.
Otherwise, C<shutdown()> will wait forever.  If a timeout occurs, the
exception "timeout while waiting for queue to flush" is thrown..

After the last job has finished, the C<after_shutdown> callback will be called
before C<shutdown()> returns (if present).  If the timeout exception is
thrown, C<after_shutdown> will not be called.

=cut

sub shutdown {
    my $self = shift;
    my $timeout = shift;
    return if $self->is_shutdown;

    croak "can't shutdown queue synchronously from the runner;".
        "use async {} to start a thread?"
        if ($self->has_runner && $self->_runner == $Coro::current);

    $self->_shutdown(1);
    $self->_chan->shutdown();

    my $t;
    if ($timeout) {
        $t = AE::timer $timeout, 0, sub {
            $self->_cv->croak("timeout while waiting for queue to flush");
            undef $t; # clear circular ref
        };
    }
    $self->_cv->end;
    $self->_cv->recv;
}

=item shutdown_nowait()

Mark the queue as shut-down (preventing new jobs from being scheduled) and
return immediately.

After the last job has finished, the C<after_shutdown> callback will be called
asynchronously (if present).

=cut

sub shutdown_nowait {
    my $self = shift;
    return if $self->is_shutdown;
    $self->_cv->end;
    $self->_shutdown(1);
    $self->_chan->shutdown();
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=back

=head1 AUTHOR

Jeremy Stashewsky C<jeremy.stashewsky@socialtext.com>

=head1 COPYRIGHT

Copyright (c) 2010 Socialtext Inc.  All rights reserved.

=cut
