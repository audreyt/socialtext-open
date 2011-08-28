package Socialtext::Job::PersonIndex;
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
    $self->arg({ user_id => $arg });
};

sub do_work {
    my $self    = shift;
    my $indexer = $self->indexer or return;

    if ($self->user) {
        $indexer->index_person($self->user);
    }
    else {
        $indexer->delete_person($self->arg->{user_id});
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::PersonIndex - index a person profile.

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->index_person($user);

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will index the profile using Solr.

=cut
