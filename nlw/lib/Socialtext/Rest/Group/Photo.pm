package Socialtext::Rest::Group::Photo;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::File;
use Socialtext::Group;
use Socialtext::Group::Photo;
use Socialtext::HTTP ':codes';
use Socialtext::Permission qw(ST_ADMIN_PERM ST_READ_PERM);
use Socialtext::JSON qw/encode_json/;
use Socialtext::Role;

use base 'Socialtext::Rest';

sub group {
   return Socialtext::Group->GetGroup( group_id => shift->group_id );
}

sub _get_photo {
    my $self = shift;
    my $rest = shift;
    my $size = shift || 'large';

    my $user  = $rest->user;
    my $group = $self->group;

    my ($photo, $status);
    if ( $group ) {
        my $can_read = $group->user_can(
            user => $user,
            permission => ST_READ_PERM,
        );
        if ($can_read) {
            $status = HTTP_200_OK;
            $photo  = $group->photo->$size;
        }
        else {
            $status = HTTP_401_Unauthorized;
            $photo  = Socialtext::Group::Photo->DefaultPhoto($size);
        }
    }
    else{
        $status = HTTP_404_Not_Found;
        $photo  = Socialtext::Group::Photo->DefaultPhoto($size);
    }

    $rest->header(
        -status        => $status,
        -pragma        => 'no-cache',
        -cache_control => 'no-cache, no-store',
        -type          => 'image/png',
    );
    return $$photo;
}

sub POST_photo {
    my $self  = shift;
    my $rest  = shift;
    my $group = $self->group;
    my $user  = $rest->user;

    # This actually returns application/json, but that messes with the
    # JSONView firefox addon, making the iframe source unparseable since it
    # captures the json data and formats it in pretty html.
    $rest->header(-type => 'text/plain');

    return $self->_post_failure(
        $rest, HTTP_404_Not_Found, 'group does not exist'
    ) unless $group;

    return $self->_post_failure(
        $rest, HTTP_401_Unauthorized, 'must be a group admin'
    ) unless $user->is_authenticated;

    my $can_admin = $group->user_can(
        user => $user,
        permission => ST_ADMIN_PERM,
    );

    return $self->_post_failure(
        $rest, HTTP_403_Forbidden, 'must be a group admin'
    ) unless $can_admin;

    my $fh = $rest->query->upload('photo-local');
    return $self->_post_failure(
        $rest, HTTP_400_Bad_Request, 'photo-local is a required argument'
    ) unless $fh;
    
    eval {
        my $blob = do { local $/; <$fh> };
        $group->photo->set( \$blob );
    };
    if ( $@ ) {
        warn $@;
        return $self->_post_failure(
            $rest, HTTP_400_Bad_Request, 'could not save image');
    }

    $rest->header($rest->header(), -status => HTTP_201_Created);
    return encode_json({
        status => 'success',
        message => 'photo uploaded'
    });
}

sub _post_failure {
    my $self    = shift;
    my $rest    = shift;
    my $status  = shift;
    my $message = shift;

    $rest->header($rest->header(), -status => $status);
    return encode_json( {status => 'failure', message => $message} );
}

sub GET_photo {
    my ($self, $rest) = @_;
    return $self->_get_photo($rest, 'large');
}

sub GET_small_photo {
    my ($self, $rest) = @_;
    return $self->_get_photo($rest, 'small');
}

1;

=head1 NAME

Socialtext::Rest::Group::Photo - Photo for a group

=head1 SYNOPSIS

    POST /data/groups/:group_id/photo

    GET /data/groups/:group_id/photo
    GET /data/groups/:group_id/small_photo

=head1 DESCRIPTION

View the photo for a group.

=cut
