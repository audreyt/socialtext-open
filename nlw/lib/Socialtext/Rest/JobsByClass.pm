package Socialtext::Rest::JobsByClass;
# @COPYRIGHT@
use Moose;

use Socialtext::Exceptions;
use Socialtext::Jobs;
use Socialtext::Job;
use Socialtext::JSON qw/encode_json/;
use Socialtext::l10n qw(loc);

extends 'Socialtext::Rest::Jobs';

{
    no strict 'refs';
    no warnings 'redefine';
    *format_timestamp = \&Socialtext::Rest::Jobs::format_timestamp;
}

sub allowed_methods {'GET'}
sub collection_name { loc('job.all=class', $_[0]->jobclass) }

sub get_resource {
    my $self = shift;
    my $jobclass = $self->jobclass;
    my $funcname = $jobclass =~ /^Socialtext::Job::/ ? $jobclass :
        "Socialtext::Job::$jobclass";
    my $now = time;
    my @jobs = 
        map { $_->{delayed} = ($_->{run_after} > $now) ? 1 : 0; $_ }
        map { Socialtext::Job->new(job => $_)->to_hash } 
        Socialtext::Jobs->list_jobs(funcname => $funcname, limit => 1000);
    return \@jobs;
}

sub _entity_hash { }

sub resource_to_html {
    my ($self, $jobs) = @_;

    my @columns = qw(jobid uniqkey priority insert_time run_after grabbed_until coalesce);
    if ($self->rest->query->param('verbose')) {
        for my $j (@$jobs) {
            $j->{arg} = YAML::Dump($j->{arg});
            $j->{arg} =~ s/^---\n//;
        }
        push @columns, 'arg';
    }
    else {
        delete $_->{arg} for @$jobs;
    }

    for my $k (qw(insert_time run_after grabbed_until)) {
        $_->{$k} = format_timestamp($_->{$k}) for @$jobs;
    }

    return $self->template_render('data/job_list.html' => { 
        jobs => $jobs,
        columns => \@columns,
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

__END__

=head1 NAME

Socialtext::Rest::JobsByClass - Show all jobs of a certain class

=head1 SYNOPSIS

  None.

=head1 DESCRIPTION

Shows the collection of ceqlotron jobs of a certain class.

=cut
