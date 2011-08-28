package Socialtext::Rest::Attachment;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest';
use Socialtext::HTTP ':codes';
use Socialtext::String ();
use Try::Tiny;

sub allowed_methods { 'GET, HEAD, DELETE' }
sub permission { +{ GET => 'read', DELETE => 'attachments' } }

# /data/workspaces/:ws/attachments/:attachment_id
# /data/workspaces/:ws/attachments/:attachment_id/:version/:filename
# subclass handles
# /data/workspaces/:ws/pages/:pname/attachments/:filename
sub GET {
    my ( $self, $rest ) = @_;
    my $rv = '';
    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('read');

    my $attachment;
    try { $attachment = $self->_get_attachment() or die "no such attachment\n" }
    catch { $rv = $self->_invalid_attachment($rest, $_) };

    if ($attachment) {
        my ($file,$size) = $attachment->prepare_to_serve(
            $self->params->{version}, 'protected');
        $rv = try { $self->serve_file($rest, $attachment, $file, $size) }
        catch { $self->_invalid_attachment($rest, $_) };
    }

    # The frontend will take care of sending the attachment.
    return $rv;
}

sub DELETE {
    my ( $self, $rest ) = @_;

    return $self->no_workspace() unless $self->workspace;

    $self->if_authorized(
        DELETE => sub {
            my $attachment = eval { $self->_get_attachment(); };
            return $self->_invalid_attachment( $rest, $@ ) if $@;

            return $self->not_authorized
                unless $self->hub->checker->can_modify_locked($attachment->page);

            if ($attachment->is_temporary) {
                $attachment->purge($attachment->page);
            }
            else {
                $attachment->delete( user => $rest->user );
            }
            $rest->header( -status => HTTP_204_No_Content );
            return '';
        }
    );
}

sub _invalid_attachment {
    my ($self, $rest, $error) = @_;
    warn $error;
    $rest->header( -status => HTTP_404_Not_Found, -type => 'text/plain' );
    $error =~ s/\n.+//m;
    $error =~ s/ at \S+ line \d+//;
    $error =~ s/\.?\s*\z//s;
    return "Invalid attachment ID. $error.\n";
}

sub _get_attachment {
    my $self = shift;
    my ($page_uri, $attachment_id) = split /:/, $self->attachment_id;
    my $attachment = $self->hub->attachments->load(
        id      => $attachment_id,
        page_id => Socialtext::String::title_to_id($page_uri),
    );
    return $attachment;
}



1;
