package Socialtext::MonitorJob;
# @COPYRIGHT@
use Moose::Role;
use Socialtext::JobCreator;
use Socialtext::Log qw/st_log/;
use Clone qw/clone/;
use Socialtext::Timer qw/time_scope/;
use namespace::clean -except => 'meta';

requires qw/Monitor_job_types finish_work Job_delay/;

sub do_work {
    my $self = shift;
    my $t = time_scope('monitor_do_work');

    (my $name = ref($self)) =~ s/^.+:://g;

    # find the count of remaining jobs we're monitoring.
    my $jobs = Socialtext::Jobs->new;
    my $count = 0;
    for my $type ($self->Monitor_job_types) {
        $count += $jobs->job_count("Socialtext::Job::$type");
    }
    if ($count) {
        st_log->info(
            "$name UPGRADE: There are $count monitored jobs remaining.");

        my @clone_args = map { $_ => $self->job->$_ }
            qw(funcid funcname priority uniqkey coalesce);
        my $next_job = TheSchwartz::Moosified::Job->new({
            @clone_args,
            run_after => time + $self->Job_delay,
            arg => {
                %{clone($self->arg)},
                last_count => $count,
            }
        });
        $self->replace_with($next_job);
    }
    else {
        st_log->info("$name UPGRADE: ".
            "There are no more monitored jobs. ".
            "Finishing work.");
        Finish_work: {
            my $t2 = time_scope('monitor_finish');
            $self->finish_work();
        }
        $self->completed();
    }
}

1;

=head1 NAME

Socialtext::MonitorJob - A Moose Role that upgrade jobs can consume
when they need to monitor the activity of one or more other types of job.

=head1 SYNOPSIS

    package MyMonitorJob

    with 'Socialtext::MonitorJob'

    sub Monitor_job_types { ... }
    sub finish_work { ... }
    sub Job_delay { ... }

=head1 DESCRIPTION

When turning on new services such as Solr or Explore, we don't want them to
activate before we build up our dataset. This role exists so that, through
monitoring jobs, we can detect when our dataset is ready to be used.

=cut
