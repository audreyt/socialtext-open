package Socialtext::Rest::Upload;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::Rest::Entity';
use Socialtext::HTTP ':codes';
use Socialtext::JSON;
use Socialtext::File;
use Socialtext::Rest::Uploads;
use Socialtext::Upload;
use File::Temp qw(tempfile);
use File::Copy qw/copy move/;
use Fatal qw/copy move/;
use Socialtext::Exceptions qw/data_validation_error/;
use Try::Tiny;

sub permission      { +{} }
sub allowed_methods {'GET'}
sub entity_name     { "Upload" }
sub nonexistence_message { "Uploaded file not found." }

sub GET {
    my ($self, $rest) = @_;
    my $rv;
    try   { $rv = $self->_GET($rest) }
    catch { $rv = $self->handle_rest_exception($_) };
    return $rv;
}

sub _GET {
    my ($self, $rest) = @_;
    my $user = $self->rest->user;

    return $self->not_authorized unless $user->is_authenticated;

    my $uuid = $self->id;

    my $upload = try { Socialtext::Upload->Get(attachment_uuid => $uuid) };
    unless ($upload &&
            $upload->is_temporary &&
            $upload->creator_id == $user->user_id) 
    {
        return $self->http_404_force;
    }

    # Support image resizing /?resize=group:small will resize for a
    # Socialtext::Group::Photo using the small version
    my $filesize;
    my $prot_uri = $upload->protected_uri;
    if (my $resize = $self->rest->query->param('resize')) {
        data_validation_error "You can only resize images"
            unless $upload->is_image;

        my ($resizer, $size) = split ':', $resize;
        $size ||= 'small';
        my $spec = Socialtext::Image::spec_resize_get($resizer,$size)
            or data_validation_error "Unknown resizer: $resizer";
        $filesize = $upload->ensure_scaled(spec => $spec);
        $prot_uri .= ".$spec";
    }
    else {
        $upload->ensure_stored();
        $filesize = $upload->content_length;
    }

    return $self->serve_file($rest, $upload, $prot_uri, $filesize);
}

1;

=head1 NAME

Socialtext::Rest::Upload - Retrieve temporarily uploaded files

=head1 SYNOPSIS

    GET /data/uploads/:id

=head1 DESCRIPTION

Grab the content of an uploaded file

=cut
