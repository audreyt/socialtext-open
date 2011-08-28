package Socialtext::Jobs;
# @COPYRIGHT@
use MooseX::Singleton;
use MooseX::AttributeInflate;
use Socialtext::TheSchwartz;
use Socialtext::SQL qw/sql_execute/;
use Module::Pluggable search_path => 'Socialtext::Job',
    sub_name => 'job_types', require => 0;
use Memoize;
use Carp qw/croak/;
use POSIX qw/strftime/;
use namespace::clean -except => [qw(meta job_types)];

has_inflated '_client' => (
    is => 'ro', isa => 'Socialtext::TheSchwartz',
    lazy_build => 1,
    handles => qr/^.+$/,
);

around 'insert' => sub {
    croak 'Use Socialtext::JobCreator->insert to create jobs'
};

memoize 'job_types';

sub load_all_jobs {
    my $self = shift;
    for my $job_type ($self->job_types) {
        eval "require $job_type";
        croak $@ if $@;
    }
}

sub can_do_all {
    my $self = shift;
    $self->load_all_jobs();
    $self->can_do($_) for $self->job_types;
}

sub can_do_long_jobs {
    my $self = shift;
    $self->load_all_jobs();
    $self->can_do($_) for grep { $_->is_long_running() } $self->job_types;
}

sub can_do_short_jobs {
    my $self = shift;
    $self->load_all_jobs();
    $self->can_do($_) for grep { !$_->is_long_running() } $self->job_types;
}

sub job_to_string {
    my $class = shift;
    my $job = shift;
    my $opts = shift || {};

    my $string = strftime "%Y-%m-%d.%H:%M:%S", localtime($job->insert_time);

    $string .= " id=" . $job->jobid;
    (my $shortname = $job->funcname) =~ s/^Socialtext::Job:://;
    $string .= ";type=$shortname";

    if ($job->uniqkey) {
        $string .= ";uniqkey=".$job->uniqkey;
    }

    my $arg = $job->arg;

    if (ref($arg) eq 'HASH') {
        if (my $ws_id = $job->arg->{workspace_id}) {
            $opts->{ws_names} ||= {};
            eval {
                $opts->{ws_names}{$ws_id} ||=
                    Socialtext::Workspace->new( workspace_id => $ws_id )->name;
                $string .= ";ws=$opts->{ws_names}{$ws_id}";
            };
            if ($@) {
                $string .= ";ws=$ws_id";
            }
        }
        $string .= ";page=".$job->arg->{page_id}
            if $job->arg->{page_id};
        $string .= ";user=".$job->arg->{user_id}
            if $job->arg->{user_id};
        $string .= ";group=".$job->arg->{group_id}
            if $job->arg->{group_id};
        $string .= ";solr=".$job->arg->{solr}
            if $job->arg->{solr};

        if ($shortname eq 'Cmd') {
            $string .= ";cmd=".$job->arg->{cmd};
            $string .= ";args=".join(',',@{$job->arg->{args} || []});
        }
    }
    elsif (!ref($arg)) {
        $string .= ';fastargs='.$arg if defined $arg;
    }

    if (my $prio = $job->priority) {
        $string .= ";priority=$prio";
    }

    if ($job->run_after > time) {
        my $when = strftime("%Y-%m-%d.%H:%M:%S", localtime($job->run_after));
        $string .= " (delayed until $when)";
    }

    $string .= " (*)" if $job->grabbed_until;

    return $string unless wantarray;
    return ($string, $shortname);
}

sub cleanup_job_tables {
    my $self = shift;
    my $logger_cb = shift || sub {};

    my @types = $self->job_types; # finds all available job modules 
    my %type_map = map {$_=>1} @types;

    my $stat = $self->stat_jobs();

    for my $job_name (keys %$stat) {
        # job module still exists: situation normal
        next if $type_map{$job_name};

        # Job module is missing.
        # Delete all jobs and remove it from the funcmap (so that it no longer
        # shows in ceq-stat and ceq-read).
        $logger_cb->($job_name);
        $self->remove_job_type($job_name);
    }
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;
