package Socialtext::Job::Upgrade::ReindexGroups;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use Socialtext::Log qw/st_log/;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

sub do_work {
    my $self = shift;

    Socialtext::Group->IndexGroups($self->arg);

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::ReindexGroups - delete and reindex groups in solr

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::ReindexGroups',
    );

=head1 DESCRIPTION

Schedules a job to be run by TheCeq which will delete all groups from Solr
and then schedule additional jobs to index each group.

=cut
