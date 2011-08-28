package Socialtext::Job::GroupIndex;
# @COPYRIGHT@
use Moose;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';
with 'Socialtext::CoalescingJob', 'Socialtext::IndexingJob';

# Called if the job argument isn't a reference type, usually because of bulk
# insertion:
override 'inflate_arg' => sub {
    my $self = shift;
    my $arg = $self->arg;
    return unless $arg;
    $self->arg({ group_id => $arg });
};

sub do_work {
    my $self    = shift;
    my $indexer = $self->indexer or return;

    if (my $group = $self->group) {
        $indexer->index_group($group);
    }
    else {
        $indexer->delete_group($self->arg->{group_id});
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::GroupIndex - index a group.

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->index_group($group);

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will index the group using Solr.

=cut
