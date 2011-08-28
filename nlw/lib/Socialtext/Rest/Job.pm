package Socialtext::Rest::Job;
# @COPYRIGHT@
use Moose;

use Socialtext::Exceptions;
use Socialtext::Jobs;
use Socialtext::Job;
use Socialtext::Rest::Jobs;

extends 'Socialtext::Rest::Entity';

{
    no strict 'refs';
    no warnings 'redefine';
    *GET_text = Socialtext::Rest::Entity::_make_getter(
        \&Socialtext::Rest::resource_to_yaml, 'text/plain');
    *GET_yaml = Socialtext::Rest::Entity::_make_getter(
        \&Socialtext::Rest::resource_to_yaml, 'text/x-yaml');
    *GET_html = Socialtext::Rest::Entity::_make_getter(
        \&resource_to_html, 'text/html');
    *{__PACKAGE__.'::if_authorized'} = \&Socialtext::Rest::Jobs::if_authorized;
    *format_timestamp = \&Socialtext::Rest::Jobs::format_timestamp;
}

has 'job' => (
    is => 'ro', isa => 'Socialtext::Job',
    lazy_build => 1,
);

sub allowed_methods {'GET'}

sub _build_job {
    my $self = shift;
    my $jobid = $self->jobid;
    my $handle = Socialtext::Jobs->job_handle($jobid);
    my $job = Socialtext::Job->new(job => $handle->job);
    return $job;
}

sub get_resource {
    my $self = shift;
    my $job = $self->job->to_hash;
    $job->{delayed} = ($job->{run_after} > time) ? 1 : 0;
    return $job;
}

sub entity_name {
    my $self = shift;
    return 'Job '.$self->jobid;
}

sub resource_to_html {
    my $self = shift;
    my $job = shift;

    delete $job->{funcid};

    my @column_order;
    {
        @column_order = qw(jobid funcname uniqkey priority insert_time run_after grabbed_until coalesce);
        # append extra keys
        my %avail = map {$_=>1} keys %$job;
        delete $avail{arg};
        delete @avail{@column_order};
        push @column_order, sort keys %avail;
        push @column_order, 'arg';
    }

    for my $k (qw(insert_time run_after grabbed_until)) {
        $job->{$k} = format_timestamp($job->{$k});
    }

    $job->{arg} = YAML::Dump($job->{arg});
    $job->{arg} =~ s/---\n//;
    return $self->template_render('data/job.html' => {
        job => $job,
        columns => \@column_order,
        entity_name => $self->entity_name,
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Rest::Job - Display info about a particular job.

=head1 SYNOPSIS

  None.

=head1 DESCRIPTION

A REST resource for a particular ceqlotron job.

=cut
