package Socialtext::Rest::WorkspacePhoto;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::HTTP ':codes';
use Socialtext;

use base 'Socialtext::Rest';

sub GET_photo {
    my ($self, $rest) = @_;
    $self->rest->header(
        -status => HTTP_302_Found,
        -Location => "/data/groups/0/photo",
    );
    return '';
}

sub GET_small_photo {
    my ($self, $rest) = @_;
    $self->rest->header(
        -status => HTTP_302_Found,
        -Location => "/data/groups/0/small_photo",
    );
    return '';
}

1;

=head1 NAME

Socialtext::Rest::Workspace::Photo - Photo for a workspace

=head1 SYNOPSIS

    GET /data/workspaces/:ws/photo
    GET /data/workspaces/:ws/small_photo

=head1 DESCRIPTION

View the photo for a workspace.

=cut
