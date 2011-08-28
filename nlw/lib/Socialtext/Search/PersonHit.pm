package Socialtext::Search::PersonHit;
# @COPYRIGHT@
use Moose;
use Socialtext::People::Profile;
use namespace::clean -except => 'meta';

has 'score'   => (is => 'ro', isa => 'Num', required => 1);
has 'user_id' => (is => 'ro', isa => 'Int', required => 1);
has 'profile' =>
    (is => 'ro', isa => 'Socialtext::People::Profile', lazy_build => 1);

sub _build_profile {
    my $self = shift;
    return Socialtext::People::Profile->GetProfile($self->user_id);
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Socialtext::Search::PersonHit - A search result hit.

=head1 SYNOPSIS

    $hit = Socialtext::Search::PersonHit->new(
       user_id => $user_id,
       score => $score,
    );

    my $score = $hit->score()
    my $profile = $hit->profile();

=head1 DESCRIPTION

This represents a search result hit and provides handy accessors.

=cut

