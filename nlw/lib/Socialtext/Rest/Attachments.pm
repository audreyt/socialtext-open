package Socialtext::Rest::Attachments;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Collection';

use Socialtext::HTTP ':codes';
use Socialtext::Base ();
use Socialtext::l10n;
use Number::Format;

sub SORTS {
    return +{
        alpha => sub {
            lcmp($Socialtext::Rest::Collection::a->{name},
                 $Socialtext::Rest::Collection::b->{name});
        },
        size => sub {
            $Socialtext::Rest::Collection::b->{'content-length'} <=>
                $Socialtext::Rest::Collection::a->{'content-length'};
        },
        alpha_date => sub {
            lcmp($Socialtext::Rest::Collection::a->{name},
                 $Socialtext::Rest::Collection::b->{name})
                or
            ($Socialtext::Rest::Collection::a->{date} <=>
                $Socialtext::Rest::Collection::b->{date});
        }
    };
}

sub allowed_methods { 'GET, HEAD, POST' }

sub _http_401 {
    my ( $self, $message ) = @_;

    $self->rest->header(
        -status => HTTP_401_Unauthorized,
        -type   => 'text/plain', );
    return $message;
}

sub bad_content {
    my ( $self, $rest ) = @_;
    $rest->header(
        -status => HTTP_415_Unsupported_Media_Type
    );
    return '';
}

sub number_formatter {
    my $self = shift;
    $self->{_formatter} ||= Number::Format->new;
    return $self->{_formatter};
}

sub _entity_hash {
    my ($self, $att) = @_;
    return $att->to_hash(formatted => 1);
}

1;

