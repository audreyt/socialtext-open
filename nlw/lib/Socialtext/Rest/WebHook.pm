package Socialtext::Rest::WebHook;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::Rest::Collection';
use Socialtext::JSON qw/encode_json decode_json/;
use Socialtext::WebHook;
use Socialtext::HTTP ':codes';

sub GET_json {
    my $self = shift;
    my $rest = shift;
    return $self->not_authorized unless $rest->user->is_business_admin;

    my $h;
    eval { $h = Socialtext::WebHook->ById( $self->hook_id ) };
    if ($@) {
        warn $@;
        $rest->header( -status => HTTP_400_Bad_Request );
        return '';
    }
    return encode_json($h->to_hash);
}

sub PUT_json {
    my $self = shift;
    my $rest = shift;
    return $self->not_authorized unless $rest->user->is_business_admin;

    my $content = $rest->getContent();
    my $object = decode_json( $content );
    if (ref($object) ne 'HASH') {
        $rest->header( -status => HTTP_400_Bad_Request );
        return 'Content should be a hash.';
    }
    my $hook;
    eval { 
        $object->{creator_id} = $rest->user->user_id;
        $hook = Socialtext::WebHook->Create(%$object),
    };
    if ($@) {
        warn $@;
        $rest->header( -status => HTTP_400_Bad_Request );
        return "$@";
    }

    $rest->header(
        -status => HTTP_201_Created,
        -Location => "/data/webhooks/" . $hook->id,
    );
    return '';
}

sub DELETE {
    my $self = shift;
    my $rest = shift;

    my $h;
    eval { $h = Socialtext::WebHook->ById( $self->hook_id ) };
    if ($@) {
        warn $@;
        $rest->header( -status => HTTP_400_Bad_Request );
        return '';
    }

    if (!$rest->user->is_business_admin) {
        if ($rest->user->user_id != $h->creator_id) {
            return $self->not_authorized;
        }
    }

    $h->delete;
    $rest->header( -status => HTTP_204_No_Content );
    return '';
}

1;
