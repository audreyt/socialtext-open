package Socialtext::CoalescingJob;
# @COPYRIGHT@
use Moose::Role;

requires qw(job do_work completed failed grab_for);

has '_also_grabbed' => (
    is => 'rw', isa => 'ArrayRef',
    default => sub { [] },
    auto_deref => 1,
);

around 'grab_for' => sub {
    return shift->(@_) + 5; # allow for time to grab other jobs
};

sub _grab_same_key {
    my $self = shift;

    my $main_job = $self->job;
    my $key      = $main_job->coalesce;
    return unless $key;

    my $class  = $main_job->funcname;
    my $client = $main_job->client;
    my @jobs;
    my $start = time;
    while (my $job = $client->find_job_with_coalescing_value($class, $key)) {
        push @jobs, $job;
        # don't spend more than 5 seconds looking for jobs
        last if (time - $start >= 5);
    }
    $self->_also_grabbed(\@jobs);
};

around 'do_work' => sub {
    my $code = shift;
    my $self = shift;

    # important to grab these before we start work to avoid race conditions
    $self->_grab_same_key();

    eval {
        $self->$code(@_);
    };
    if ($@) {
        $self->failed($@, 255);
    }
    elsif (!$self->job->did_something) {
        $self->failed("coalescing job didn't explicitly complete");
    }
};

after 'failed' => sub {
    my $self = shift;
    my $msg = shift;
    my $exit_status = shift;

    return unless $self->_also_grabbed;

    local $@;
    for my $job ($self->_also_grabbed) {
        $job->failed($msg,$exit_status);
    }
};

after 'completed' => sub {
    my $self = shift;

    return unless $self->_also_grabbed;

    local $@;
    my @ids;
    for my $job ($self->_also_grabbed) {
        $job->completed;
        push @ids, $job->jobid;
    }

    # for reporting, pretend it was an arg
    $self->job->arg->{coalesced} = scalar(@ids) if @ids;
};

no Moose::Role;
1;

=head1 NAME

Socialtext::CoalescingJob

=head1 SYNOPSIS

    package MyJob;
    use Moose;
    extends 'Socialtext::Job';
    with 'Socialtext::CoalescingJob';

    sub do_work { ... }

=head1 DESCRIPTION

Causes jobs with matching coalesce values to also be completed if this job is
successful.  Jobs without coalescing keys are skipped.

Only jobs created B<before> this one starts running are considered in order to
prevent a race condition.

=cut
