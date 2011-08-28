package Socialtext::Job::AttachmentIndex;
# @COPYRIGHT@
use Moose;

extends 'Socialtext::Job', 'Socialtext::Job::AttachmentIndex::Base';
with 'Socialtext::CoalescingJob', 'Socialtext::IndexingJob';

use constant 'check_skip_index' => 1;

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
no Moose;

package Socialtext::Job::AttachmentIndex::Base;
use Moose;
use Socialtext::Attachments;

sub do_work {
    my $self = shift;
    my $args = $self->arg;
    my $indexer = $self->indexer
        or die "can't create indexer";

    my $page = eval { $self->page };
    # this should be done in the builder for ->page, but just in case:
    unless ($page && $page->active) {
        $self->permanent_failure(
            "No page $args->{page_id} in workspace $args->{workspace_id}\n"
        );
        return;
    }

    my $page_id = $page->id;
    my $attachment = $page->hub->attachments->load(
        id      => $args->{attach_id},
        page_id => $page_id,
        deleted_ok => 1,
    );
    $attachment->_page($page); # avoid lazy-loading

    if ($attachment->deleted) {
        $indexer->delete_attachment($page_id, $attachment->id);
    }
    else {
        $indexer->index_attachment($page_id, $attachment,
            $self->check_skip_index);
    }

    $self->completed();
}

__PACKAGE__->meta->make_immutable(inline_constructor => 1);
no Moose;
1;
__END__

=head1 NAME

Socialtext::Job::AttachmentIndex - index an attachment

=head1 SYNOPSIS

  use Socialtext::JobCreator;
  Socialtext::JobCreator->index_attachment($attachment, $config);

=head1 DESCRIPTION

Index a page attachment.

=cut
