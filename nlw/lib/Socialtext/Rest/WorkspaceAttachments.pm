package Socialtext::Rest::WorkspaceAttachments;
# @COPYRIGHT@

use warnings;
use strict;

use Socialtext::Attachment;

use base 'Socialtext::Rest::Attachments';

sub allowed_methods { 'GET, HEAD' }

sub _entities_for_query {
    my $self = shift;
    my $q = $self->rest->query;

    my $term = $q->param('q') || $q->param('filter');
    if ($term) {
        my %params = map { $q->param($_) ? ($_ => $q->param($_)) : () }
            qw(order limit offset);

        my ($hits) = Socialtext::Attachment->Search(
            search_term => $term,
            workspace => $self->hub->current_workspace,
            %params,
        );

        return map { $self->hub->attachments->load(
            id => $_->attachment_id,
            page_id => $_->page_uri,
        ) } @$hits;
        return ();
    }
    else {
        return @{$self->hub->attachments->all_attachments_in_workspace()};
    }
}

1;

