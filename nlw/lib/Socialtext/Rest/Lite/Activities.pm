package Socialtext::Rest::Lite::Activities;
# @COPYRIGHT@
use Moose;
use Socialtext::HTTP qw(:codes);
use Socialtext::l10n qw(loc);
use Socialtext::Lite::Signals;
use namespace::clean -except => 'meta';

extends 'Socialtext::Rest::Lite';

=head1 NAME

Socialtext::Rest::Lite::Activities

=head1 SYNOPSIS

Wrapper around Socialtext::Lite::Activities

=head1 DESCRIPTION

Fetches types of events for miki activities.

=cut

sub if_authorized {
    my ( $self, $method, $perl_method, @args ) = @_;

    if ((uc($method) eq 'GET') && Socialtext::HTTP::Cookie->NeedsRenewal) {
        return $self->renew_authentication();
    }

    my $user = $self->rest->user;
    return $self->not_authorized unless $user and $user->is_authenticated;

    return $self->$perl_method(@args);
}

sub GET_activities {
    my ($self, $rest) = @_;
    $self->if_authorized(
        'GET',
        sub {
            my $lite = Socialtext::Lite::Activities->new(hub => $self->hub);
            my %args;
            $args{$_} = $rest->query->param($_) for $rest->query->param;
            $args{pagenum} = delete $args{page};
            my $content = $lite->activities(%args);

            $rest->header(
                -status => HTTP_200_OK,
                -type   => 'text/html; charset=UTF-8'
            );
            return $content;
        }
    );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
