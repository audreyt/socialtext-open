package Socialtext::Rest::PageAttachments;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Socialtext::Rest::Attachments';

use Socialtext::SQL qw/sql_txn/;
use Fcntl ':seek';
use File::Temp;
use Socialtext::HTTP ':codes';
use Socialtext::Attachment;

=head2 POST

Create a new attachment.  The name must be passed in using the C<name> CGI
parameter.  If creation is successful, return 201 and the Location: of
the new attachment.

=cut

sub POST {
    my ( $self, $rest ) = @_;

    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('attachments');
    my $lock_check_failed = $self->page_lock_permission_fail();
    return $lock_check_failed if ($lock_check_failed);

    my $content_type = $rest->request->header_in('Content-Type');
    unless ($content_type) {
        $rest->header(
            -status => HTTP_409_Conflict,
            -type   => 'text/plain',
        );
        return 'Content-type header required';
    }
    my $page = $self->page;
    $self->hub->pages->current($page);

    my $content_fh = File::Temp->new();
    print $content_fh $rest->getContent;
    seek $content_fh, 0, SEEK_SET;

    # read the ?name= and replace query parameters
    # (REST::Application can't do this)
    my $replace = Apache::Request->new(Apache->request)->param('replace');
    my $name = Apache::Request->new(Apache->request)->param('name')
        or return $self->_http_401(
            'You must supply a value for the "name" parameter.' );

    sql_txn { 
        if ($replace) {
            my $with_name = $self->hub->attachments->all(filename => $name);
            for my $att (@$with_name) {
                $att->is_temporary ? $att->purge() : $att->delete();
            }
        }

        my $att = $self->hub->attachments->create(
            filename     => $name,
            fh           => $content_fh,
            creator      => $rest->user,
            Content_type => $content_type,
            page         => $page,
            embed        => 0, # don't inline a wafl for the ReST API
        );
        my $base = $self->rest->query->url( -base => 1 );
        $rest->header(
            -status   => HTTP_201_Created,
            -Location => $base . $att->download_uri('files'),
        );
    };

    # {bz: 4286}: Record edit_save events for attachment uploads via ReST too.
    # XXX: UGH seriously? pass the page content all the way through?!
    $page->update_from_remote(user => $rest->user, content => $page->content);

    return '';
}

sub allowed_methods { 'GET, HEAD, POST' }

sub get_resource {
    my $self = shift;
    my $q = $self->rest->query;

    my $atts;
    my %params = map { $q->param($_) ? ($_ => $q->param($_)) : () }
        qw(order limit offset);
    my $term = $q->param('q') || $q->param('filter');

    if ($term) {
        my ($hits) = Socialtext::Attachment->Search(
            search_term => $term,
            workspace => $self->hub->current_workspace,
            page_id => $self->page->id,
            %params,
        );

        $atts = [
            map { $self->hub->attachments->load(
                id => $_->attachment_id,
                page_id => $_->page_uri,
            ) } @$hits
        ];
    }
    else {
        $atts = $self->hub->attachments->all(
            page_id => $self->page->id,
            %params,
        );
    }

    return [ map { $self->_entity_hash($_) } @$atts ];
}

1;
