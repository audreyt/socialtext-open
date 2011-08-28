package Socialtext::Search::GroupHit;
# @COPYRIGHT@
use Moose;
use Socialtext::Group;
use namespace::clean -except => 'meta';

=head1 NAME

Socialtext::Search::GroupHit - A search result hit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::GroupHit->new(
       group_id => $group_id,
       score => $score,
    );

    my $score = $hit->score()
    my $group = $hit->group();

=head1 DESCRIPTION

This represents a search result hit and provides handy accessors.

=cut

has 'score'    => (is => 'ro', isa => 'Num', required => 1);
has 'group_id' => (is => 'ro', isa => 'Int', required => 1);
has 'group'    => (is => 'ro', isa => 'Socialtext::Group', lazy_build => 1);

sub _build_group {
    my $self = shift;
    return Socialtext::Group->GetGroup(group_id => $self->group_id);
}

__PACKAGE__->meta->make_immutable;
1;
