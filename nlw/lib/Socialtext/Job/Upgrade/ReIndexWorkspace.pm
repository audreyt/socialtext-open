package Socialtext::Job::Upgrade::ReIndexWorkspace;
# @COPYRIGHT@
use Moose;
use Socialtext::JobCreator;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

# Generating the ReIndex jobs can take a very long time so the grab_for is set
# to 5 hours just in case we hit a hideously-large workspace in the field.
override 'grab_for' => sub { 5 * 3600 };

sub do_work {
    my $self = shift;
    my $hub = $self->hub;

    my $regex = $self->arg->{page_content_matches};
    $regex = qr/$regex/o if $regex;

    my $solr_indexer = Socialtext::Search::Solr::Factory->create_indexer();
    for my $page_id ( $hub->pages->all_ids() ) {
        my $page = $hub->pages->new_page($page_id);
        next unless $page and $page->exists and !$page->deleted;

        if ($regex) {
            my $ref = $page->body_ref;
            next unless ($ref and $$ref =~ $regex);
        }

        Socialtext::JobCreator->index_page(
            $page, undef,
            page_job_class => 'Socialtext::Job::PageReIndex',
            attachment_job_class => 'Socialtext::Job::AttachmentReIndex',
            indexers => [ $solr_indexer ],
            priority => -32,
        );
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Upgrade::ReIndexWorkspace - Index workspace stuff again

=head1 SYNOPSIS

  use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Upgrade::ReIndexWorkspace', {
            workspace_id => $workspace_id,
            page_content_matches => $regex, # optional
        },
    );

=head1 DESCRIPTION

Finds all Pages and attachments in the specified Workspace and makes a
PageReIndex or AttachmentReIndex job for them.

=cut
