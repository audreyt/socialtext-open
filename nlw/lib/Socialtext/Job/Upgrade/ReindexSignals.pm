package Socialtext::Job::Upgrade::ReindexSignals;
# @COPYRIGHT@
use Moose;
use Socialtext::Signal;
use Socialtext::JobCreator;
use Socialtext::SQL qw/sql_execute/;
use Socialtext::Log qw/st_log/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

sub do_work {
    my $self = shift;

    # First, delete all the signals from Solr.
    unless ($self->arg && $self->arg->{no_delete}) {
        st_log()->info("deleting all signals from solr");
        my $factory = Socialtext::Search::Solr::Factory->new;
        $factory->create_indexer()->delete_signals();
    }

    # Now create jobs to index each signal
    my $sth = sql_execute(
        'SELECT signal_id FROM signal order by signal_id DESC');
    my @jobs;
    while (my ($id) = $sth->fetchrow_array) {
        push @jobs, {
            coalesce => "$id-reindex", # don't coalesce with normal jobs
            arg => $id."-1-1"
        };
    }
    st_log()->info("going to insert ".scalar(@jobs)." SignalReIndex jobs");
    my $template_job = TheSchwartz::Moosified::Job->new(
        funcname => 'Socialtext::Job::SignalReIndex',
        priority => -30,
    );
    Socialtext::JobCreator->bulk_insert($template_job, \@jobs);
    st_log()->info("done SignalReIndex bulk_insert");

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::ReindexSignals - Delete signals from Solr & reindex

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::ReindexSignals',
    );

=head1 DESCRIPTION

Schedules a job to be run by TheCeq which will delete all signals from Solr
and then schedule additional jobs to index each signal.

=cut
